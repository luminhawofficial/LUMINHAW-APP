begin;

drop index if exists public.premium_payment_transaction_reference_unique;
create unique index premium_payment_transaction_reference_unique
  on public.premium_payment_requests (
    regexp_replace(merchant_transaction_reference, '[^0-9]', '', 'g')
  )
  where merchant_transaction_reference ~ '^[0-9[:space:]]+$';

drop function if exists public.submit_premium_payment(
  uuid, uuid, text, date, time, text, jsonb
);

create or replace function public.submit_premium_payment(
  p_user_id uuid,
  p_payment_request_id uuid,
  p_transaction_reference text,
  p_payment_date date,
  p_payment_time time,
  p_amount_centavos integer,
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
  submitted_timestamp timestamptz;
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
  submitted_timestamp := case
    when p_payment_time is null then null
    else (p_payment_date + p_payment_time) at time zone 'Asia/Manila'
  end;

  if not found or current_request.payment_status <> 'pending'
    or coalesce(p_transaction_reference, '') !~ '^[0-9 ]+$'
    or normalized_reference !~ '^[0-9]{13}$'
    or p_payment_date is null
    or p_payment_date > (now() at time zone 'Asia/Manila')::date
    or p_payment_date < (now() at time zone 'Asia/Manila')::date - 90
    or p_amount_centavos is null
    or p_amount_centavos <= 0
    or p_amount_centavos <> current_request.amount_centavos
    or (submitted_timestamp is not null and submitted_timestamp > now())
    or p_proof_storage_path is null
    or p_proof_storage_path not like
      p_user_id::text || '/' || p_payment_request_id::text || '/%'
    or p_ocr_result is not null
  then
    return 'validation_failed';
  end if;

  update public.premium_payment_requests
  set merchant_transaction_reference = normalized_reference,
      payment_date = p_payment_date,
      payment_time = p_payment_time,
      proof_storage_path = p_proof_storage_path,
      payment_status = 'under_review',
      ocr_reference_number = null,
      ocr_transaction_date = null,
      ocr_transaction_time = null,
      ocr_amount_centavos = null,
      ocr_recipient = null,
      ocr_transaction_status = null,
      ocr_confidence = null,
      ocr_status = null,
      image_quality_status = 'needs_manual_review',
      rejection_reason = null,
      review_notes = 'Awaiting manual payment verification.',
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
    'proof_submitted_for_manual_review',
    jsonb_build_object(
      'image_quality_status', 'needs_manual_review',
      'reference_verified', false
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
  when invalid_text_representation or numeric_value_out_of_range
    or datetime_field_overflow then
    return 'validation_failed';
end;
$$;

revoke all on function public.submit_premium_payment(
  uuid, uuid, text, date, time, integer, text, jsonb
) from public, anon, authenticated;
grant execute on function public.submit_premium_payment(
  uuid, uuid, text, date, time, integer, text, jsonb
) to service_role;

commit;
