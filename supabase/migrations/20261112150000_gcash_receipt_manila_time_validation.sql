begin;

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
  receipt_timestamp timestamptz;
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
  receipt_timestamp := (
    nullif(p_ocr_result->>'transactionDate', '')::date +
    nullif(p_ocr_result->>'transactionTime', '')::time
  ) at time zone 'Asia/Manila';
  submitted_timestamp := (p_payment_date + p_payment_time)
    at time zone 'Asia/Manila';
  date_matches := receipt_timestamp is not null
    and submitted_timestamp is not null
    and abs(extract(epoch from (receipt_timestamp - submitted_timestamp))) <= 300;
  time_matches := date_matches;
  amount_matches := nullif(p_ocr_result->>'amountCentavos', '')::integer
    is not distinct from current_request.amount_centavos;

  if not found or current_request.payment_status <> 'pending'
    or normalized_reference !~ '^[0-9]{13}$'
    or p_payment_date is null
    or p_payment_date > (now() at time zone 'Asia/Manila')::date
    or p_payment_date < (now() at time zone 'Asia/Manila')::date - 90
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
    or receipt_timestamp > now()
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
    or coalesce(nullif(p_ocr_result->>'imageWidth', '')::integer, 0) < 300
    or coalesce(nullif(p_ocr_result->>'imageHeight', '')::integer, 0) < 300
    or coalesce((p_ocr_result->>'duplicateReference')::boolean, true) is not false
    or (
      p_ocr_result ? 'recipientNumber'
      and coalesce(p_ocr_result->>'recipientNumber', '')
        !~ '^09[0-9]{9}$'
    )
    or (
      p_ocr_result ? 'recipientMatch'
      and coalesce((p_ocr_result->>'recipientMatch')::boolean, false) is not true
    )
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
    or not (
      reference_matches and date_matches and time_matches and amount_matches
    )
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
      ocr_recipient = left(
        coalesce(
          nullif(p_ocr_result->>'recipientNumber', ''),
          nullif(p_ocr_result->>'recipient', '')
        ),
        200
      ),
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
      'amount_match', amount_matches,
      'recipient_match', coalesce(
        (p_ocr_result->>'recipientMatch')::boolean,
        true
      )
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
  uuid, uuid, text, date, time, text, jsonb
) from public, anon, authenticated;
grant execute on function public.submit_premium_payment(
  uuid, uuid, text, date, time, text, jsonb
) to service_role;

commit;
