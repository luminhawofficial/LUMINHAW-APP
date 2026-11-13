create or replace function public.admin_review_premium_payment(
  p_actor_id uuid,
  p_payment_request_id uuid,
  p_decision text,
  p_confirm_received boolean,
  p_review_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_request public.premium_payment_requests%rowtype;
  selected_plan public.payment_plans%rowtype;
  updated_request public.premium_payment_requests%rowtype;
  actor_email text;
  entitlement_expiry timestamptz;
begin
  if p_actor_id is null
    or p_payment_request_id is null
    or p_decision is null
    or p_decision not in ('approve', 'reject')
    or (p_decision = 'approve' and p_confirm_received is not true)
    or (p_decision = 'reject'
      and length(pg_catalog.btrim(coalesce(p_review_notes, '')))
        not between 1 and 1000)
    or length(coalesce(p_review_notes, '')) > 1000
    or not exists (
      select 1
      from public.admin_roles
      where user_id = p_actor_id
        and role = 'admin'
        and status = 'active'
    )
  then
    raise exception 'Unauthorized or invalid payment review.';
  end if;

  select lower(email) into actor_email
  from auth.users
  where id = p_actor_id;

  if actor_email is null then
    raise exception 'Administrator account not found.';
  end if;

  select * into current_request
  from public.premium_payment_requests
  where id = p_payment_request_id
  for update;

  if not found or current_request.payment_status <> 'under_review' then
    raise exception 'Payment is not awaiting review.';
  end if;

  if p_decision = 'approve'
    and lower(coalesce(current_request.customer_email, '')) = actor_email
  then
    raise exception 'An administrator cannot approve their own payment.';
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

    select greatest(
      coalesce(pg_catalog.max(expires_at) filter (
        where status = 'active' and expires_at > pg_catalog.now()
      ), pg_catalog.now()),
      pg_catalog.now()
    )
    into entitlement_expiry
    from public.subscription_entitlements
    where user_id = current_request.user_id;

    entitlement_expiry := entitlement_expiry
      + pg_catalog.make_interval(days => selected_plan.duration_days);

    insert into public.subscription_entitlements (
      user_id, product_id, status, expires_at, verified_at, updated_at
    )
    values (
      current_request.user_id,
      'manual_gcash',
      'active',
      entitlement_expiry,
      pg_catalog.now(),
      pg_catalog.now()
    )
    on conflict (user_id, product_id) do update
    set status = 'active',
        expires_at = excluded.expires_at,
        verified_at = excluded.verified_at,
        updated_at = excluded.updated_at;

    update public.premium_payment_requests
    set payment_status = 'approved',
        reviewed_by = p_actor_id,
        reviewed_by_email = null,
        reviewed_at = pg_catalog.now(),
        transaction_received_confirmed = true,
        entitlement_expires_at = entitlement_expiry,
        review_notes = nullif(pg_catalog.btrim(coalesce(p_review_notes, '')), ''),
        rejection_reason = null,
        updated_at = pg_catalog.now()
    where id = current_request.id
    returning * into updated_request;
  else
    update public.premium_payment_requests
    set payment_status = 'rejected',
        reviewed_by = p_actor_id,
        reviewed_by_email = null,
        reviewed_at = pg_catalog.now(),
        transaction_received_confirmed = false,
        review_notes = pg_catalog.btrim(p_review_notes),
        rejection_reason = pg_catalog.btrim(p_review_notes),
        updated_at = pg_catalog.now()
    where id = current_request.id
    returning * into updated_request;
  end if;

  insert into public.premium_payment_events (
    payment_request_id, actor_id, previous_status, new_status, event_type,
    metadata
  )
  values (
    current_request.id,
    p_actor_id,
    'under_review',
    updated_request.payment_status,
    'admin_review',
    jsonb_build_object(
      'decision', p_decision,
      'transaction_received_confirmed', p_decision = 'approve',
      'entitlement_expires_at', updated_request.entitlement_expires_at
    )
  );

  insert into public.admin_activity_logs (
    actor_id, action, resource_type, resource_id, metadata
  )
  values (
    p_actor_id,
    'payment.reviewed',
    'payment',
    current_request.id::text,
    jsonb_build_object(
      'decision', p_decision,
      'payment_status', updated_request.payment_status
    )
  );

  return jsonb_build_object(
    'payment_request_id', updated_request.id,
    'decision', p_decision,
    'payment_status', updated_request.payment_status,
    'entitlement_expires_at', updated_request.entitlement_expires_at
  );
end;
$$;

revoke all on function public.admin_review_premium_payment(uuid, uuid, text, boolean, text)
  from public, anon, authenticated;
grant execute on function public.admin_review_premium_payment(uuid, uuid, text, boolean, text)
  to service_role;
