alter table public.premium_payment_requests
  add column if not exists reviewed_by_email text,
  add column if not exists payment_time time,
  add column if not exists ocr_transaction_time time;

do $$
declare
  existing_check text;
begin
  select pg_get_expr(conbin, conrelid)
  into existing_check
  from pg_constraint
  where conrelid = 'public.premium_payment_requests'::regclass
    and conname = 'premium_payment_requests_gcash_reference_format_check';

  if existing_check is null then
    alter table public.premium_payment_requests
      add constraint premium_payment_requests_gcash_reference_format_check
      check (
        merchant_transaction_reference is null
        or merchant_transaction_reference ~ '^[0-9]{13}$'
      ) not valid;
  elsif existing_check <>
    '((merchant_transaction_reference IS NULL) OR (merchant_transaction_reference ~ ''^[0-9]{13}$''::text))'
  then
    raise exception
      'Constraint premium_payment_requests_gcash_reference_format_check exists with an unexpected definition.';
  end if;
end $$;

alter table public.premium_payment_requests
  drop constraint if exists premium_payment_requests_review_state_check;

alter table public.premium_payment_requests
  add constraint premium_payment_requests_review_state_check
  check (
    (
      payment_status in ('pending', 'under_review', 'cancelled', 'expired')
      and reviewed_by is null
      and reviewed_by_email is null
      and reviewed_at is null
    )
    or (
      payment_status in ('approved', 'rejected')
      and reviewed_at is not null
      and (
        (reviewed_by is not null and reviewed_by_email is null)
        or (reviewed_by is null and reviewed_by_email is not null)
      )
    )
    or (
      payment_status = 'rejected'
      and reviewed_by is null
      and reviewed_by_email is null
      and reviewed_at is null
      and ocr_status = 'mismatch'
      and rejection_reason is not null
    )
  );

create table if not exists public.payment_email_action_tokens (
  id uuid primary key default gen_random_uuid(),
  payment_request_id uuid not null
    references public.premium_payment_requests (id) on delete cascade,
  action text not null check (action in ('approve', 'reject')),
  reviewer_email text not null
    check (lower(reviewer_email) = 'luminhawofficial@gmail.com'),
  token_hash text not null unique
    check (token_hash ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists payment_email_action_tokens_request_idx
  on public.payment_email_action_tokens (payment_request_id, action, created_at desc);
create index if not exists payment_email_action_tokens_expiry_idx
  on public.payment_email_action_tokens (expires_at)
  where consumed_at is null and revoked_at is null;
create unique index if not exists payment_email_action_tokens_one_active_action_idx
  on public.payment_email_action_tokens (payment_request_id, action)
  where consumed_at is null and revoked_at is null;

alter table public.payment_email_action_tokens enable row level security;
revoke all on public.payment_email_action_tokens from public, anon, authenticated;
grant all on public.payment_email_action_tokens to service_role;

drop policy if exists "Verified users can read enabled payment plans"
  on public.payment_plans;
create policy "Verified users can read enabled payment plans"
  on public.payment_plans for select to authenticated
  using (
    enabled
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );

create table if not exists public.payment_email_action_rate_limits (
  rate_key text not null check (rate_key ~ '^[0-9a-f]{64}$'),
  window_number bigint not null,
  request_count integer not null check (request_count > 0),
  primary key (rate_key, window_number)
);
create index if not exists payment_email_action_rate_limits_window_idx
  on public.payment_email_action_rate_limits (window_number);

alter table public.payment_email_action_rate_limits enable row level security;
revoke all on public.payment_email_action_rate_limits
  from public, anon, authenticated;
grant all on public.payment_email_action_rate_limits to service_role;

create or replace function public.consume_payment_email_action_rate_limit(
  p_rate_key text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_window bigint;
  current_count integer;
begin
  if p_rate_key is null
    or p_rate_key !~ '^[0-9a-f]{64}$'
    or p_limit is null
    or p_limit < 1
    or p_limit > 10000
    or p_window_seconds is null
    or p_window_seconds < 1
    or p_window_seconds > 86400
  then
    raise exception 'Invalid email action rate limit parameters.';
  end if;

  current_window := floor(
    extract(epoch from pg_catalog.clock_timestamp()) / p_window_seconds
  )::bigint;
  delete from public.payment_email_action_rate_limits
  where window_number < current_window - 2;

  insert into public.payment_email_action_rate_limits as counters (
    rate_key, window_number, request_count
  )
  values (p_rate_key, current_window, 1)
  on conflict (rate_key, window_number)
  do update set request_count = counters.request_count + 1
  returning request_count into current_count;
  return current_count <= p_limit;
end;
$$;

revoke all on function public.consume_payment_email_action_rate_limit(
  text, integer, integer
) from public, anon, authenticated;
grant execute on function public.consume_payment_email_action_rate_limit(
  text, integer, integer
) to service_role;

alter table public.payment_email_notifications
  add column if not exists delivery_claimed_at timestamptz,
  add column if not exists delivery_claim_token uuid;

alter table public.payment_email_notifications
  drop constraint if exists payment_email_notifications_delivery_status_check;
alter table public.payment_email_notifications
  add constraint payment_email_notifications_delivery_status_check
  check (delivery_status in ('pending', 'sending', 'sent', 'failed'));

create or replace function public.claim_payment_email_notification(
  p_notification_id uuid
)
returns table (
  claimed boolean,
  attempt_count integer,
  claim_token uuid
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  update public.payment_email_notifications as notification
  set delivery_status = 'sending',
      delivery_claimed_at = now(),
      delivery_claim_token = gen_random_uuid(),
      attempt_count = notification.attempt_count + 1,
      updated_at = now()
  where notification.id = p_notification_id
    and notification.delivery_status <> 'sent'
    and (
      notification.delivery_status <> 'sending'
      or notification.delivery_claimed_at < now() - interval '15 minutes'
    )
  returning true, notification.attempt_count, notification.delivery_claim_token;
  if not found then
    return query select false, 0, null::uuid;
  end if;
end;
$$;

revoke all on function public.claim_payment_email_notification(uuid)
  from public, anon, authenticated;
grant execute on function public.claim_payment_email_notification(uuid)
  to service_role;

create or replace function public.replace_payment_email_action_tokens(
  p_notification_id uuid,
  p_claim_token uuid,
  p_approve_token_hash text,
  p_reject_token_hash text,
  p_expires_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_notification public.payment_email_notifications%rowtype;
  selected_payment public.premium_payment_requests%rowtype;
begin
  if p_notification_id is null
    or p_claim_token is null
    or p_approve_token_hash is null
    or p_approve_token_hash !~ '^[0-9a-f]{64}$'
    or p_reject_token_hash is null
    or p_reject_token_hash !~ '^[0-9a-f]{64}$'
    or p_approve_token_hash = p_reject_token_hash
    or p_expires_at is null
    or p_expires_at <= now()
    or p_expires_at > now() + interval '49 hours'
  then
    raise exception 'Invalid email payment action token set.';
  end if;

  select * into selected_notification
  from public.payment_email_notifications
  where id = p_notification_id
  for update;
  if not found
    or selected_notification.notification_type <> 'admin_payment_submitted'
    or lower(btrim(selected_notification.recipient_email))
      <> 'luminhawofficial@gmail.com'
    or selected_notification.delivery_status <> 'sending'
    or selected_notification.delivery_claim_token <> p_claim_token
  then
    raise exception 'Payment notification claim is invalid.';
  end if;

  select * into selected_payment
  from public.premium_payment_requests
  where id = selected_notification.payment_request_id
  for update;
  if not found or selected_payment.payment_status <> 'under_review' then
    raise exception 'Payment is not awaiting email verification.';
  end if;

  update public.payment_email_action_tokens
  set revoked_at = now()
  where payment_request_id = selected_payment.id
    and consumed_at is null
    and revoked_at is null;

  insert into public.payment_email_action_tokens (
    payment_request_id, action, reviewer_email, token_hash, expires_at
  )
  values
    (
      selected_payment.id,
      'approve',
      'luminhawofficial@gmail.com',
      p_approve_token_hash,
      p_expires_at
    ),
    (
      selected_payment.id,
      'reject',
      'luminhawofficial@gmail.com',
      p_reject_token_hash,
      p_expires_at
    );
end;
$$;

revoke all on function public.replace_payment_email_action_tokens(
  uuid, uuid, text, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.replace_payment_email_action_tokens(
  uuid, uuid, text, text, timestamptz
) to service_role;

create or replace function public.payment_reference_exists(
  p_reference text,
  p_payment_request_id uuid
)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1
    from public.premium_payment_requests as payment
    where payment.id <> p_payment_request_id
      and payment.merchant_transaction_reference is not null
      and regexp_replace(
        payment.merchant_transaction_reference,
        '[^0-9]',
        '',
        'g'
      ) = p_reference
  );
$$;

revoke all on function public.payment_reference_exists(text, uuid)
  from public, anon, authenticated;
grant execute on function public.payment_reference_exists(text, uuid)
  to service_role;

create or replace function public.queue_customer_payment_review_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.payment_status is distinct from new.payment_status
    and new.payment_status in ('approved', 'rejected')
    and (new.reviewed_by is not null or new.reviewed_by_email is not null)
    and new.customer_email is not null
  then
    insert into public.payment_email_notifications (
      payment_request_id, notification_type, recipient_email
    )
    values (
      new.id, 'customer_payment_reviewed', new.customer_email
    )
    on conflict (payment_request_id, notification_type) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists premium_payment_review_email_queue
  on public.premium_payment_requests;
create trigger premium_payment_review_email_queue
after update of payment_status on public.premium_payment_requests
for each row execute function public.queue_customer_payment_review_email();

create or replace function public.submit_premium_payment(
  p_user_id uuid,
  p_payment_request_id uuid,
  p_transaction_reference text,
  p_payment_date date,
  p_payment_time time,
  p_proof_storage_path text,
  p_ocr_result jsonb
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_request public.premium_payment_requests%rowtype;
  normalized_reference text;
  ocr_reference text;
  ocr_status_value text;
  provider_identification text;
  confidence_value numeric;
  reference_matches boolean;
  date_matches boolean;
  time_matches boolean;
  amount_matches boolean;
begin
  select * into current_request
  from public.premium_payment_requests
  where id = p_payment_request_id and user_id = p_user_id
  for update;

  normalized_reference := regexp_replace(
    coalesce(p_transaction_reference, ''),
    '[^0-9]',
    '',
    'g'
  );
  ocr_reference := regexp_replace(
    coalesce(p_ocr_result->>'referenceNumber', ''),
    '[^0-9]',
    '',
    'g'
  );
  ocr_status_value := p_ocr_result->>'status';
  provider_identification := p_ocr_result->>'providerIdentification';
  confidence_value := nullif(p_ocr_result->>'confidence', '')::numeric;
  reference_matches := ocr_reference = normalized_reference;
  date_matches := nullif(p_ocr_result->>'transactionDate', '')::date
    is not distinct from p_payment_date;
  time_matches := nullif(p_ocr_result->>'transactionTime', '')::time
    is not distinct from p_payment_time;
  amount_matches := nullif(p_ocr_result->>'amountCentavos', '')::integer
    is not distinct from current_request.amount_centavos;

  if not found or current_request.payment_status <> 'pending'
    or normalized_reference !~ '^[0-9]{13}$'
    or p_payment_date is null
    or p_payment_date > current_date
    or p_payment_date < current_date - 90
    or p_payment_time is null
    or p_proof_storage_path is null
    or p_proof_storage_path not like
      p_user_id::text || '/' || p_payment_request_id::text || '/%'
    or p_ocr_result is null
    or pg_catalog.octet_length(p_ocr_result::text) > 4096
    or ocr_status_value is null
    or ocr_status_value not in ('matched', 'manual_review')
    or ocr_reference !~ '^[0-9]{13}$'
    or nullif(p_ocr_result->>'transactionDate', '') is null
    or nullif(p_ocr_result->>'transactionTime', '') is null
    or nullif(p_ocr_result->>'amountCentavos', '') is null
    or coalesce(p_ocr_result->>'transactionStatus', '') <> 'successful'
    or coalesce((p_ocr_result->>'validImage')::boolean, false) is not true
    or coalesce((p_ocr_result->>'hasTransactionMarkers')::boolean, false)
      is not true
    or provider_identification is null
    or provider_identification not in ('gcash', 'ambiguous')
    or (
      provider_identification = 'gcash'
      and coalesce((p_ocr_result->>'isGcashReceipt')::boolean, false)
        is not true
    )
    or (
      provider_identification = 'ambiguous'
      and (
        ocr_status_value <> 'manual_review'
        or coalesce((p_ocr_result->>'isGcashReceipt')::boolean, true)
      )
    )
    or (
      ocr_status_value = 'matched'
      and (
        provider_identification <> 'gcash'
        or coalesce((p_ocr_result->>'imageReadable')::boolean, false)
          is not true
      )
    )
    or coalesce(nullif(p_ocr_result->>'imageWidth', '')::integer, 0) < 640
    or coalesce(nullif(p_ocr_result->>'imageHeight', '')::integer, 0) < 480
    or coalesce((p_ocr_result->>'duplicateReference')::boolean, true) is not false
  then
    return 'validation_failed';
  end if;

  if
    coalesce((p_ocr_result->>'referenceMatch')::boolean, false)
      is distinct from reference_matches
    or coalesce((p_ocr_result->>'dateMatch')::boolean, false)
      is distinct from date_matches
    or coalesce((p_ocr_result->>'timeMatch')::boolean, false)
      is distinct from time_matches
    or coalesce((p_ocr_result->>'amountMatch')::boolean, false)
      is distinct from amount_matches
    or (ocr_status_value = 'matched' and not (
      reference_matches and date_matches and time_matches and amount_matches
    ))
    or (ocr_status_value = 'manual_review' and (
      reference_matches and date_matches and time_matches and amount_matches
      and provider_identification <> 'ambiguous'
      and confidence_value is not null
    ))
  then
    return 'validation_failed';
  end if;

  if
    (confidence_value is null and ocr_status_value = 'matched')
    or (confidence_value is not null and (
      confidence_value < 0.75 or confidence_value > 1
    ))
  then
    return 'validation_failed';
  end if;

  update public.premium_payment_requests
  set merchant_transaction_reference = normalized_reference,
      payment_date = p_payment_date,
      payment_time = p_payment_time,
      proof_storage_path = p_proof_storage_path,
      payment_status = 'under_review',
      ocr_reference_number = ocr_reference,
      ocr_transaction_date =
        nullif(p_ocr_result->>'transactionDate', '')::date,
      ocr_transaction_time =
        nullif(p_ocr_result->>'transactionTime', '')::time,
      ocr_amount_centavos =
        nullif(p_ocr_result->>'amountCentavos', '')::integer,
      ocr_recipient = left(nullif(p_ocr_result->>'recipient', ''), 200),
      ocr_transaction_status = 'successful',
      ocr_confidence = confidence_value,
      ocr_status = ocr_status_value,
      image_quality_status = case
        when ocr_status_value = 'matched' then 'clear'
        else 'needs_manual_review'
      end,
      rejection_reason = null,
      review_notes = case
        when ocr_status_value = 'manual_review'
          then left(nullif(p_ocr_result->>'reason', ''), 500)
        else null
      end,
      updated_at = now()
  where id = current_request.id;

  insert into public.premium_payment_events (
    payment_request_id, actor_id, previous_status, new_status, event_type,
    metadata
  )
  values (
    current_request.id,
    p_user_id,
    'pending',
    'under_review',
    case
      when ocr_status_value = 'matched' then 'proof_validated'
      else 'proof_submitted_for_manual_review'
    end,
    jsonb_build_object(
      'ocr_status', ocr_status_value,
      'image_quality_status', case
        when ocr_status_value = 'matched' then 'clear'
        else 'needs_manual_review'
      end,
      'reference_match', reference_matches,
      'date_match', date_matches,
      'time_match', time_matches,
      'amount_match', amount_matches
    )
  );

  insert into public.payment_email_notifications (
    payment_request_id, notification_type, recipient_email
  )
  values (
    current_request.id,
    'admin_payment_submitted',
    'luminhawofficial@gmail.com'
  )
  on conflict (payment_request_id, notification_type) do nothing;

  return 'under_review';
exception
  when unique_violation then
    return 'duplicate_reference';
  when invalid_text_representation or numeric_value_out_of_range then
    return 'validation_failed';
end;
$$;

create or replace function public.review_premium_payment_by_email_token(
  p_token_hash text,
  p_decision text,
  p_confirm_received boolean,
  p_rejection_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_token public.payment_email_action_tokens%rowtype;
  current_request public.premium_payment_requests%rowtype;
  selected_plan public.payment_plans%rowtype;
  current_entitlement public.subscription_entitlements%rowtype;
  entitlement_start timestamptz;
  entitlement_expiry timestamptz;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$'
    or p_decision is null
    or p_decision not in ('approve', 'reject')
    or (p_decision = 'approve' and p_confirm_received is not true)
    or (p_decision = 'reject'
      and length(btrim(coalesce(p_rejection_reason, ''))) not between 1 and 1000)
  then
    raise exception 'Invalid email payment action.';
  end if;

  select * into selected_token
  from public.payment_email_action_tokens
  where token_hash = p_token_hash;
  if not found
    or selected_token.action <> p_decision
    or selected_token.expires_at <= now()
    or selected_token.consumed_at is not null
    or selected_token.revoked_at is not null
    or selected_token.reviewer_email <> 'luminhawofficial@gmail.com'
  then
    raise exception 'Email payment action is invalid or expired.';
  end if;

  select * into current_request
  from public.premium_payment_requests
  where id = selected_token.payment_request_id
  for update;
  if not found or current_request.payment_status <> 'under_review' then
    raise exception 'Payment is not awaiting email verification.';
  end if;
  if p_decision = 'approve'
    and lower(current_request.customer_email) = 'luminhawofficial@gmail.com'
  then
    raise exception 'A customer cannot approve their own payment.';
  end if;

  select * into selected_token
  from public.payment_email_action_tokens
  where token_hash = p_token_hash
  for update;
  if not found
    or selected_token.action <> p_decision
    or selected_token.expires_at <= now()
    or selected_token.consumed_at is not null
    or selected_token.revoked_at is not null
    or selected_token.reviewer_email <> 'luminhawofficial@gmail.com'
  then
    raise exception 'Email payment action is invalid or expired.';
  end if;

  update public.payment_email_action_tokens
  set consumed_at = now()
  where id = selected_token.id;
  update public.payment_email_action_tokens
  set revoked_at = now()
  where payment_request_id = selected_token.payment_request_id
    and id <> selected_token.id
    and consumed_at is null
    and revoked_at is null;

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
    select * into current_entitlement
    from public.subscription_entitlements
    where user_id = current_request.user_id
      and product_id = 'manual_gcash'
    for update;

    entitlement_start := case
      when found
        and current_entitlement.status = 'active'
        and current_entitlement.expires_at > now()
        then current_entitlement.expires_at
      else now()
    end;
    entitlement_expiry :=
      entitlement_start + make_interval(days => selected_plan.duration_days);

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

    update public.premium_payment_requests
    set payment_status = 'approved',
        reviewed_by = null,
        reviewed_by_email = 'luminhawofficial@gmail.com',
        reviewed_at = now(),
        transaction_received_confirmed = true,
        entitlement_expires_at = entitlement_expiry,
        review_notes = null,
        rejection_reason = null,
        updated_at = now()
    where id = current_request.id;
  else
    update public.premium_payment_requests
    set payment_status = 'rejected',
        reviewed_by = null,
        reviewed_by_email = 'luminhawofficial@gmail.com',
        reviewed_at = now(),
        transaction_received_confirmed = false,
        review_notes = btrim(p_rejection_reason),
        rejection_reason = btrim(p_rejection_reason),
        updated_at = now()
    where id = current_request.id;
    entitlement_expiry := null;
  end if;

  insert into public.premium_payment_events (
    payment_request_id, actor_id, previous_status, new_status, event_type,
    metadata
  )
  values (
    current_request.id,
    null,
    'under_review',
    case when p_decision = 'approve' then 'approved' else 'rejected' end,
    'email_review',
    jsonb_build_object(
      'decision', p_decision,
      'reviewer_email', 'luminhawofficial@gmail.com',
      'transaction_received_confirmed', p_decision = 'approve',
      'entitlement_expires_at', entitlement_expiry
    )
  );

  return jsonb_build_object(
    'payment_request_id', current_request.id,
    'decision', p_decision,
    'entitlement_expires_at', entitlement_expiry
  );
end;
$$;

revoke all on function public.submit_premium_payment(
  uuid, uuid, text, date, time, text, jsonb
) from public, anon, authenticated;
grant execute on function public.submit_premium_payment(
  uuid, uuid, text, date, time, text, jsonb
) to service_role;

revoke all on function public.submit_premium_payment(
  uuid, uuid, text, date, text, jsonb
) from public, anon, authenticated, service_role;

revoke all on function public.review_premium_payment_by_email_token(
  text, text, boolean, text
) from public, anon, authenticated;
grant execute on function public.review_premium_payment_by_email_token(
  text, text, boolean, text
) to service_role;

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
begin
  raise exception 'Email-based payment review is required.';
end;
$$;

revoke all on function public.review_premium_payment(uuid, uuid, text, text)
  from public, anon, authenticated, service_role;

revoke all on function public.admin_manage_premium_entitlement(
  uuid, uuid, text, text, integer, text
) from public, anon, authenticated, service_role;
