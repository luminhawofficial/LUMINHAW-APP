alter table public.premium_payment_requests
  add column if not exists customer_full_name text,
  add column if not exists customer_mobile_number text,
  add column if not exists customer_email text,
  add column if not exists ocr_reference_number text,
  add column if not exists ocr_transaction_date date,
  add column if not exists ocr_amount_centavos integer,
  add column if not exists ocr_recipient text,
  add column if not exists ocr_transaction_status text
    check (ocr_transaction_status in ('successful', 'failed', 'unknown')),
  add column if not exists ocr_confidence numeric(5, 4)
    check (ocr_confidence between 0 and 1),
  add column if not exists ocr_status text
    check (ocr_status in ('matched', 'manual_review', 'mismatch')),
  add column if not exists image_quality_status text
    check (image_quality_status in ('clear', 'needs_manual_review')),
  add column if not exists rejection_reason text;

alter table public.premium_payment_requests
  drop constraint if exists premium_payment_requests_check;
alter table public.premium_payment_requests
  add constraint premium_payment_requests_review_state_check
  check (
    (
      payment_status in ('pending', 'under_review', 'cancelled', 'expired')
      and reviewed_by is null
      and reviewed_at is null
    )
    or (
      payment_status in ('approved', 'rejected')
      and reviewed_by is not null
      and reviewed_at is not null
    )
    or (
      payment_status = 'rejected'
      and reviewed_by is null
      and reviewed_at is null
      and ocr_status = 'mismatch'
      and rejection_reason is not null
    )
  );

do $$
begin
  if exists (
    select 1
    from public.premium_payment_requests
    where merchant_transaction_reference is not null
    group by upper(regexp_replace(
      btrim(merchant_transaction_reference),
      '[^A-Za-z0-9]',
      '',
      'g'
    ))
    having count(*) > 1
  ) then
    raise exception
      'Existing GCash references collide after normalization; reconcile them before applying this migration.';
  end if;
end;
$$;

drop index if exists public.premium_payment_transaction_reference_unique;
create unique index premium_payment_transaction_reference_unique
  on public.premium_payment_requests (
    upper(regexp_replace(btrim(merchant_transaction_reference), '[^A-Za-z0-9]', '', 'g'))
  )
  where merchant_transaction_reference is not null;

update storage.buckets
set allowed_mime_types = array['image/jpeg', 'image/png']
where id = 'premium-payment-proofs';

create table if not exists public.payment_email_notifications (
  id uuid primary key default gen_random_uuid(),
  payment_request_id uuid not null
    references public.premium_payment_requests (id) on delete cascade,
  notification_type text not null
    check (notification_type in (
      'admin_payment_submitted',
      'customer_payment_reviewed'
    )),
  recipient_email text not null check (
    recipient_email ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'
  ),
  delivery_status text not null default 'pending'
    check (delivery_status in ('pending', 'sent', 'failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  provider_message_id text,
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  delivered_at timestamptz,
  unique (payment_request_id, notification_type)
);

create or replace function public.queue_customer_payment_review_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.payment_status is distinct from new.payment_status
    and new.payment_status in ('approved', 'rejected')
    and new.reviewed_by is not null
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

create trigger premium_payment_review_email_queue
after update of payment_status on public.premium_payment_requests
for each row execute function public.queue_customer_payment_review_email();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'gcash-payment-assets',
  'gcash-payment-assets',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

alter table public.payment_email_notifications enable row level security;
revoke all on public.payment_email_notifications from public, anon, authenticated;
grant all on public.payment_email_notifications to service_role;

create or replace function public.create_premium_payment_request(
  p_user_id uuid,
  p_plan_code text,
  p_payment_reference text,
  p_customer_full_name text,
  p_customer_mobile_number text,
  p_customer_email text
)
returns public.premium_payment_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_plan public.payment_plans%rowtype;
  created_request public.premium_payment_requests%rowtype;
begin
  if p_user_id is null or p_plan_code is null
    or p_payment_reference is null
    or length(p_payment_reference) not between 8 and 80
    or length(btrim(coalesce(p_customer_full_name, ''))) not between 2 and 120
    or p_customer_mobile_number is null
    or p_customer_mobile_number !~ '^\+639[0-9]{9}$'
    or p_customer_email is null
    or p_customer_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'
  then
    raise exception 'Invalid payment request.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text, 0)
  );

  if exists (
    select 1 from public.premium_payment_requests
    where user_id = p_user_id
      and payment_status in ('pending', 'under_review')
  ) then
    raise exception 'Payment request already open.';
  end if;

  select * into selected_plan
  from public.payment_plans
  where code = p_plan_code and enabled
  for share;

  if not found then
    raise exception 'Payment plan unavailable.';
  end if;

  insert into public.premium_payment_requests (
    user_id, plan_id, amount_centavos, currency, unique_payment_reference,
    customer_full_name, customer_mobile_number, customer_email
  )
  values (
    p_user_id,
    selected_plan.id,
    selected_plan.amount_centavos,
    selected_plan.currency,
    p_payment_reference,
    btrim(p_customer_full_name),
    p_customer_mobile_number,
    lower(btrim(p_customer_email))
  )
  returning * into created_request;

  insert into public.premium_payment_events (
    payment_request_id, actor_id, previous_status, new_status, event_type
  )
  values (
    created_request.id, p_user_id, null, 'pending', 'request_created'
  );

  return created_request;
end;
$$;

create or replace function public.submit_premium_payment(
  p_user_id uuid,
  p_payment_request_id uuid,
  p_transaction_reference text,
  p_payment_date date,
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
  next_status text;
  ocr_status_value text;
  rejection_reason_value text;
  confidence_value numeric;
begin
  select * into current_request
  from public.premium_payment_requests
  where id = p_payment_request_id and user_id = p_user_id
  for update;

  if not found or current_request.payment_status <> 'pending'
    or p_transaction_reference is null
    or length(btrim(p_transaction_reference)) not between 6 and 80
    or length(regexp_replace(
      btrim(p_transaction_reference),
      '[^A-Za-z0-9]',
      '',
      'g'
    )) < 6
    or p_payment_date is null
    or p_payment_date > current_date
    or p_payment_date < current_date - 90
    or p_proof_storage_path is null
    or p_proof_storage_path not like p_user_id::text || '/' || p_payment_request_id::text || '/%'
    or p_ocr_result is null
    or pg_catalog.octet_length(p_ocr_result::text) > 4096
  then
    return 'not_submittable';
  end if;

  ocr_status_value := p_ocr_result->>'status';
  if ocr_status_value is null or
    ocr_status_value not in ('matched', 'manual_review', 'mismatch')
  then
    return 'invalid_ocr_result';
  end if;

  confidence_value := nullif(p_ocr_result->>'confidence', '')::numeric;
  if confidence_value is not null and
    (confidence_value < 0 or confidence_value > 1)
  then
    return 'invalid_ocr_result';
  end if;

  next_status := case
    when ocr_status_value = 'mismatch' then 'rejected'
    else 'under_review'
  end;
  rejection_reason_value := case
    when next_status = 'rejected'
      then left(coalesce(p_ocr_result->>'reason', 'Receipt did not match the submitted payment.'), 500)
    else null
  end;

  update public.premium_payment_requests
  set merchant_transaction_reference = upper(regexp_replace(
        btrim(p_transaction_reference),
        '[^A-Za-z0-9]',
        '',
        'g'
      )),
      payment_date = p_payment_date,
      proof_storage_path = p_proof_storage_path,
      payment_status = next_status,
      ocr_reference_number = nullif(upper(regexp_replace(
        coalesce(p_ocr_result->>'referenceNumber', ''),
        '[^A-Za-z0-9]',
        '',
        'g'
      )), ''),
      ocr_transaction_date = nullif(p_ocr_result->>'transactionDate', '')::date,
      ocr_amount_centavos = nullif(p_ocr_result->>'amountCentavos', '')::integer,
      ocr_recipient = left(nullif(p_ocr_result->>'recipient', ''), 200),
      ocr_transaction_status = coalesce(
        nullif(p_ocr_result->>'transactionStatus', ''),
        'unknown'
      ),
      ocr_confidence = confidence_value,
      ocr_status = ocr_status_value,
      image_quality_status = case
        when confidence_value >= 0.75
          and coalesce(nullif(p_ocr_result->>'imageWidth', '')::integer, 0) >= 640
          and coalesce(nullif(p_ocr_result->>'imageHeight', '')::integer, 0) >= 480
          then 'clear'
        else 'needs_manual_review'
      end,
      rejection_reason = rejection_reason_value,
      review_notes = rejection_reason_value,
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
    next_status,
    case when next_status = 'rejected'
      then 'receipt_ocr_rejected'
      else 'proof_submitted'
    end,
    jsonb_build_object(
      'ocr_status', ocr_status_value,
      'image_quality_status', case
        when ocr_status_value = 'matched' then 'clear'
        else 'needs_manual_review'
      end
    )
  );

  insert into public.payment_email_notifications (
    payment_request_id, notification_type, recipient_email
  )
  values (
    current_request.id, 'admin_payment_submitted', 'luminhawofficial@gmail.com'
  )
  on conflict (payment_request_id, notification_type) do nothing;
  if next_status = 'rejected' and current_request.customer_email is not null then
    insert into public.payment_email_notifications (
      payment_request_id, notification_type, recipient_email
    )
    values (
      current_request.id,
      'customer_payment_reviewed',
      current_request.customer_email
    )
    on conflict (payment_request_id, notification_type) do nothing;
  end if;

  return next_status;
exception
  when unique_violation then
    return 'duplicate_reference';
  when invalid_text_representation or numeric_value_out_of_range then
    return 'invalid_ocr_result';
end;
$$;

revoke all on function public.create_premium_payment_request(uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.create_premium_payment_request(uuid, text, text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.submit_premium_payment(uuid, uuid, text, date, text)
  from public, anon, authenticated, service_role;
revoke all on function public.submit_premium_payment(uuid, uuid, text, date, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.create_premium_payment_request(uuid, text, text, text, text, text)
  to service_role;
grant execute on function public.submit_premium_payment(uuid, uuid, text, date, text, jsonb)
  to service_role;
