alter table public.premium_payment_requests
  add column if not exists transaction_received_confirmed boolean
    not null default false;

create or replace function public.review_premium_payment(
  p_payment_request_id uuid,
  p_reviewer_id uuid,
  p_decision text,
  p_review_notes text
)
returns public.premium_payment_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_request public.premium_payment_requests%rowtype;
  selected_plan public.payment_plans%rowtype;
  current_manual_entitlement public.subscription_entitlements%rowtype;
  updated_request public.premium_payment_requests%rowtype;
  entitlement_start timestamptz;
  entitlement_expiry timestamptz;
  confirmation_marker constant text := 'GCASH_RECEIVED_CONFIRMED:';
  admin_review_notes text;
begin
  if p_reviewer_id is null or p_decision is null
    or p_decision not in ('approve', 'reject')
    or (p_decision = 'reject'
      and length(btrim(coalesce(p_review_notes, ''))) = 0)
    or length(coalesce(p_review_notes, '')) > 1100
    or not exists (
      select 1 from public.payment_admins
      where user_id = p_reviewer_id
    )
  then
    raise exception 'Unauthorized or invalid review request.';
  end if;

  if p_decision = 'approve' and
    left(btrim(coalesce(p_review_notes, '')), length(confirmation_marker))
      <> confirmation_marker
  then
    raise exception 'Confirmation of actual GCash receipt is required.';
  end if;

  select * into current_request
  from public.premium_payment_requests
  where id = p_payment_request_id
  for update;
  if not found or current_request.payment_status <> 'under_review' then
    raise exception 'Payment is not awaiting review.';
  end if;

  if p_decision = 'approve' then
    select * into selected_plan
    from public.payment_plans
    where id = current_request.plan_id;
    if not found then
      raise exception 'Payment plan not found.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(current_request.user_id::text, 0)
    );

    select * into current_manual_entitlement
    from public.subscription_entitlements
    where user_id = current_request.user_id
      and product_id = 'manual_gcash'
    for update;

    entitlement_start := case
      when found
        and current_manual_entitlement.status = 'active'
        and current_manual_entitlement.expires_at > now()
        then current_manual_entitlement.expires_at
      else now()
    end;
    entitlement_expiry := entitlement_start
      + make_interval(days => selected_plan.duration_days);

    insert into public.subscription_entitlements (
      user_id, product_id, status, expires_at, verified_at, updated_at
    )
    values (
      current_request.user_id,
      'manual_gcash',
      'active',
      entitlement_expiry,
      now(),
      now()
    )
    on conflict (user_id, product_id) do update
    set status = 'active',
        expires_at = excluded.expires_at,
        verified_at = excluded.verified_at,
        updated_at = excluded.updated_at;

    admin_review_notes := nullif(
      btrim(substr(
        btrim(p_review_notes),
        length(confirmation_marker) + 1
      )),
      ''
    );
    update public.premium_payment_requests
    set payment_status = 'approved',
        review_notes = admin_review_notes,
        reviewed_by = p_reviewer_id,
        reviewed_at = now(),
        transaction_received_confirmed = true,
        entitlement_expires_at = entitlement_expiry,
        updated_at = now()
    where id = current_request.id
    returning * into updated_request;
  else
    update public.premium_payment_requests
    set payment_status = 'rejected',
        review_notes = btrim(p_review_notes),
        reviewed_by = p_reviewer_id,
        reviewed_at = now(),
        updated_at = now()
    where id = current_request.id
    returning * into updated_request;
  end if;

  insert into public.premium_payment_events (
    payment_request_id,
    actor_id,
    previous_status,
    new_status,
    event_type,
    metadata
  )
  values (
    current_request.id,
    p_reviewer_id,
    'under_review',
    updated_request.payment_status,
    'admin_review',
    jsonb_build_object(
      'decision', p_decision,
      'transaction_received_confirmed',
        updated_request.transaction_received_confirmed,
      'entitlement_expires_at', updated_request.entitlement_expires_at
    )
  );

  return updated_request;
end;
$$;

revoke all on function public.review_premium_payment(uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.review_premium_payment(uuid, uuid, text, text)
  to service_role;
