begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

select plan(30);

select ok(
  not has_function_privilege(
    'anon',
    'public.create_premium_payment_request(uuid, text, text, text, text, text)',
    'EXECUTE'
  ),
  'anonymous users cannot create payment requests'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_premium_payment_request(uuid, text, text, text, text, text)',
    'EXECUTE'
  ),
  'authenticated users cannot bypass the payment Edge Function'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.create_premium_payment_request(uuid, text, text, text, text, text)',
    'EXECUTE'
  ),
  'the trusted payment function can create requests'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.submit_premium_payment(uuid, uuid, text, date, time, integer, text, jsonb)',
    'EXECUTE'
  ),
  'authenticated users cannot bypass server-side receipt validation'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.submit_premium_payment(uuid, uuid, text, date, time, integer, text, jsonb)',
    'EXECUTE'
  ),
  'the trusted submission function can accept manual receipt submissions'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.submit_premium_payment(uuid, uuid, text, date, time, integer, text, jsonb)',
    'EXECUTE'
  ),
  'anonymous users cannot submit payment receipts'
);

select ok(
  to_regprocedure(
    'public.submit_premium_payment(uuid, uuid, text, date, text, jsonb)'
  ) is null
  or (
    not has_function_privilege(
      'anon',
      'public.submit_premium_payment(uuid, uuid, text, date, text, jsonb)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'authenticated',
      'public.submit_premium_payment(uuid, uuid, text, date, text, jsonb)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'service_role',
      'public.submit_premium_payment(uuid, uuid, text, date, text, jsonb)',
      'EXECUTE'
    )
  ),
  'the obsolete six-argument submission RPC is absent or inaccessible'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.payment_email_notifications',
    'SELECT'
  ),
  'customers cannot read payment notification records'
);

select ok(
  exists (
    select 1 from storage.buckets
    where id = 'gcash-payment-assets' and public = false
  ),
  'the configurable GCash QR bucket is private'
);

select ok(
  exists (
    select 1 from storage.buckets
    where id = 'premium-payment-proofs' and public = false
  ),
  'customer payment proofs remain in private storage'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
values (
  '00000000-0000-4000-8000-000000000501',
  'authenticated',
  'authenticated',
  'payment-manual-review-test@example.com',
  '',
  now(),
  '{}'::jsonb,
  '{}'::jsonb
);

insert into public.premium_payment_requests (
  id, user_id, plan_id, amount_centavos, currency,
  unique_payment_reference, payment_status, customer_email
)
values (
  '00000000-0000-4000-8000-000000000502',
  '00000000-0000-4000-8000-000000000501',
  (select id from public.payment_plans where code = 'premium_30_days'),
  4900,
  'PHP',
  'LUM-PGTEST-MANUAL-001',
  'pending',
  'payment-manual-review-test@example.com'
);

select is(
  public.submit_premium_payment(
    '00000000-0000-4000-8000-000000000501',
    '00000000-0000-4000-8000-000000000502',
    '1234567890123',
    current_date - 1,
    '09:42',
    4900,
    '00000000-0000-4000-8000-000000000501/00000000-0000-4000-8000-000000000502/receipt.jpg',
    jsonb_build_object(
      'referenceNumber', '1234567890123',
      'transactionDate', (current_date - 1)::text,
      'transactionTime', '9:35 AM',
      'amountCentavos', 4900,
      'transactionStatus', 'successful',
      'confidence', 0.95,
      'imageWidth', 1080,
      'imageHeight', 1920,
      'validImage', true,
      'providerIdentification', 'gcash',
      'hasTransactionMarkers', true,
      'isGcashReceipt', true,
      'imageReadable', true,
      'referenceMatch', true,
      'dateMatch', false,
      'timeMatch', false,
      'amountMatch', true,
      'duplicateReference', false,
      'status', 'manual_review',
      'reason', 'The transaction time differs.'
    )
  ),
  'validation_failed',
  'OCR-bearing submissions are rejected because OCR is disabled'
);

select is(
  (
    select payment_status
    from public.premium_payment_requests
    where id = '00000000-0000-4000-8000-000000000502'
  ),
  'pending'::text,
  'a submission containing OCR data does not enter the review queue'
);

select is(
  (
    select ocr_status
    from public.premium_payment_requests
    where id = '00000000-0000-4000-8000-000000000502'
  ),
  null::text,
  'a rejected receipt does not record OCR as submitted'
);

select is(
  (
    select count(*)::integer
    from public.payment_email_notifications
    where payment_request_id = '00000000-0000-4000-8000-000000000502'
      and notification_type = 'admin_payment_submitted'
  ),
  0,
  'a mismatching receipt does not queue administrator email review'
);

insert into public.premium_payment_requests (
  id, user_id, plan_id, amount_centavos, currency,
  unique_payment_reference, payment_status, customer_email
)
values (
  '00000000-0000-4000-8000-000000000505',
  '00000000-0000-4000-8000-000000000501',
  (select id from public.payment_plans where code = 'premium_30_days'),
  4900,
  'PHP',
  'LUM-PGTEST-OCR-SPACE-001',
  'pending',
  'payment-manual-review-test@example.com'
);

select is(
  public.submit_premium_payment(
    '00000000-0000-4000-8000-000000000501',
    '00000000-0000-4000-8000-000000000505',
    '1234567890125',
    current_date - 1,
    '09:42',
    4900,
    '00000000-0000-4000-8000-000000000501/00000000-0000-4000-8000-000000000505/receipt.jpg',
    null
  ),
  'under_review',
  'a receipt is accepted for manual review without any OCR result'
);

select ok(
  (
    select ocr_reference_number is null
      and ocr_transaction_date is null
      and ocr_transaction_time is null
      and ocr_amount_centavos is null
      and ocr_recipient is null
      and ocr_transaction_status is null
      and ocr_confidence is null
      and ocr_status is null
      and image_quality_status = 'needs_manual_review'
    from public.premium_payment_requests
    where id = '00000000-0000-4000-8000-000000000505'
  ),
  'receipt detail extraction fields remain null during manual review'
);

select is(
  (
    select count(*)::integer
    from public.subscription_entitlements
    where user_id = '00000000-0000-4000-8000-000000000501'
      and product_id = 'manual_gcash'
  ),
  0,
  'a submission awaiting manual review does not activate Premium'
);

insert into public.premium_payment_requests (
  id, user_id, plan_id, amount_centavos, currency,
  unique_payment_reference, payment_status, customer_email
)
values
  (
    '00000000-0000-4000-8000-000000000506',
    '00000000-0000-4000-8000-000000000501',
    (select id from public.payment_plans where code = 'premium_30_days'),
    4900,
    'PHP',
    'LUM-PGTEST-NULL-CONFIDENCE-001',
    'pending',
    'payment-manual-review-test@example.com'
  ),
  (
    '00000000-0000-4000-8000-000000000507',
    '00000000-0000-4000-8000-000000000501',
    (select id from public.payment_plans where code = 'premium_30_days'),
    4900,
    'PHP',
    'LUM-PGTEST-MATCHED-NULL-001',
    'pending',
    'payment-manual-review-test@example.com'
  ),
  (
    '00000000-0000-4000-8000-000000000508',
    '00000000-0000-4000-8000-000000000501',
    (select id from public.payment_plans where code = 'premium_30_days'),
    4900,
    'PHP',
    'LUM-PGTEST-LOW-CONFIDENCE-001',
    'pending',
    'payment-manual-review-test@example.com'
  ),
  (
    '00000000-0000-4000-8000-000000000509',
    '00000000-0000-4000-8000-000000000501',
    (select id from public.payment_plans where code = 'premium_30_days'),
    4900,
    'PHP',
    'LUM-PGTEST-HIGH-CONFIDENCE-001',
    'pending',
    'payment-manual-review-test@example.com'
  );

select is(
  public.submit_premium_payment(
    '00000000-0000-4000-8000-000000000501',
    '00000000-0000-4000-8000-000000000506',
    '1234567890126',
    current_date - 1,
    '09:42',
    4900,
    '00000000-0000-4000-8000-000000000501/00000000-0000-4000-8000-000000000506/receipt.jpg',
    null
  ),
  'under_review',
  'a receipt with no OCR data is accepted only for manual review'
);

select ok(
  (
    select payment_status = 'under_review'
      and ocr_status is null
      and ocr_reference_number is null
      and ocr_transaction_date is null
      and ocr_transaction_time is null
      and ocr_amount_centavos is null
      and ocr_recipient is null
      and ocr_transaction_status is null
      and ocr_confidence is null
      and image_quality_status = 'needs_manual_review'
    from public.premium_payment_requests
    where id = '00000000-0000-4000-8000-000000000506'
  ),
  'manual submission stores no extracted receipt details or confidence'
);

select is(
  public.submit_premium_payment(
    '00000000-0000-4000-8000-000000000501',
    '00000000-0000-4000-8000-000000000507',
    '1234567890127',
    current_date - 1,
    '09:42',
    4900,
    '00000000-0000-4000-8000-000000000501/00000000-0000-4000-8000-000000000507/receipt.jpg',
    jsonb_build_object(
      'referenceNumber', '1234567890127',
      'transactionDate', (current_date - 1)::text,
      'transactionTime', '09:42',
      'amountCentavos', 4900,
      'transactionStatus', 'successful',
      'confidence', null,
      'imageWidth', 1080,
      'imageHeight', 1920,
      'validImage', true,
      'providerIdentification', 'gcash',
      'hasTransactionMarkers', true,
      'isGcashReceipt', true,
      'imageReadable', true,
      'referenceMatch', true,
      'dateMatch', true,
      'timeMatch', true,
      'amountMatch', true,
      'duplicateReference', false,
      'status', 'matched',
      'reason', null
    )
  ),
  'validation_failed',
  'OCR-generated matched status cannot be supplied to the RPC'
);

select is(
  public.submit_premium_payment(
    '00000000-0000-4000-8000-000000000501',
    '00000000-0000-4000-8000-000000000508',
    '1234567890128',
    current_date - 1,
    '09:42',
    4900,
    '00000000-0000-4000-8000-000000000501/00000000-0000-4000-8000-000000000508/receipt.jpg',
    jsonb_build_object(
      'referenceNumber', '1234567890128',
      'transactionDate', (current_date - 1)::text,
      'transactionTime', '09:42',
      'amountCentavos', 4900,
      'transactionStatus', 'successful',
      'confidence', 0.6,
      'imageWidth', 1080,
      'imageHeight', 1920,
      'validImage', true,
      'providerIdentification', 'gcash',
      'hasTransactionMarkers', true,
      'isGcashReceipt', true,
      'imageReadable', false,
      'referenceMatch', true,
      'dateMatch', true,
      'timeMatch', true,
      'amountMatch', true,
      'duplicateReference', false,
      'status', 'manual_review',
      'reason', 'OCR confidence is below the accepted range.'
    )
  ),
  'validation_failed',
  'OCR-generated confidence data cannot be supplied to the RPC'
);

select is(
  public.submit_premium_payment(
    '00000000-0000-4000-8000-000000000501',
    '00000000-0000-4000-8000-000000000509',
    '1234567890129',
    current_date - 1,
    '09:42',
    4900,
    '00000000-0000-4000-8000-000000000501/00000000-0000-4000-8000-000000000509/receipt.jpg',
    jsonb_build_object(
      'referenceNumber', '1234567890129',
      'transactionDate', (current_date - 1)::text,
      'transactionTime', '09:42',
      'amountCentavos', 4900,
      'transactionStatus', 'successful',
      'confidence', 1.01,
      'imageWidth', 1080,
      'imageHeight', 1920,
      'validImage', true,
      'providerIdentification', 'gcash',
      'hasTransactionMarkers', true,
      'isGcashReceipt', true,
      'imageReadable', false,
      'referenceMatch', true,
      'dateMatch', true,
      'timeMatch', true,
      'amountMatch', true,
      'duplicateReference', false,
      'status', 'manual_review',
      'reason', 'OCR confidence is above the accepted range.'
    )
  ),
  'validation_failed',
  'OCR-generated confidence data cannot be supplied to the RPC'
);

select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'premium_payment_transaction_reference_unique'
      and indexdef ilike '%unique%'
      and indexdef ilike '%regexp_replace%'
  ),
  'normalized transaction references have a database unique index'
);

insert into public.premium_payment_requests (
  id, user_id, plan_id, amount_centavos, currency,
  unique_payment_reference, payment_status, customer_email
)
values (
  '00000000-0000-4000-8000-000000000510',
  '00000000-0000-4000-8000-000000000501',
  (select id from public.payment_plans where code = 'premium_30_days'),
  4900,
  'PHP',
  'LUM-PGTEST-OPTIONAL-TIME-001',
  'pending',
  'payment-manual-review-test@example.com'
);

select is(
  public.submit_premium_payment(
    '00000000-0000-4000-8000-000000000501',
    '00000000-0000-4000-8000-000000000510',
    '1234567890130',
    current_date - 1,
    null,
    4900,
    '00000000-0000-4000-8000-000000000501/00000000-0000-4000-8000-000000000510/receipt.jpg',
    null
  ),
  'under_review',
  'a valid submission does not require transaction time'
);

select ok(
  (
    select payment_time is null
    from public.premium_payment_requests
    where id = '00000000-0000-4000-8000-000000000510'
  ),
  'a missing transaction time is stored as null'
);

insert into public.premium_payment_requests (
  id, user_id, plan_id, amount_centavos, currency,
  unique_payment_reference, payment_status, customer_email
)
values
  (
    '00000000-0000-4000-8000-000000000511',
    '00000000-0000-4000-8000-000000000501',
    (select id from public.payment_plans where code = 'premium_30_days'),
    4900,
    'PHP',
    'LUM-PGTEST-INVALID-REFERENCE-001',
    'pending',
    'payment-manual-review-test@example.com'
  ),
  (
    '00000000-0000-4000-8000-000000000512',
    '00000000-0000-4000-8000-000000000501',
    (select id from public.payment_plans where code = 'premium_30_days'),
    4900,
    'PHP',
    'LUM-PGTEST-WRONG-AMOUNT-001',
    'pending',
    'payment-manual-review-test@example.com'
  ),
  (
    '00000000-0000-4000-8000-000000000513',
    '00000000-0000-4000-8000-000000000501',
    (select id from public.payment_plans where code = 'premium_30_days'),
    4900,
    'PHP',
    'LUM-PGTEST-FUTURE-DATE-001',
    'pending',
    'payment-manual-review-test@example.com'
  ),
  (
    '00000000-0000-4000-8000-000000000516',
    '00000000-0000-4000-8000-000000000501',
    (select id from public.payment_plans where code = 'premium_30_days'),
    4900,
    'PHP',
    'LUM-PGTEST-MISSING-RECEIPT-001',
    'pending',
    'payment-manual-review-test@example.com'
  );

select is(
  public.submit_premium_payment(
    '00000000-0000-4000-8000-000000000501',
    '00000000-0000-4000-8000-000000000511',
    '1234567890 12X3',
    current_date - 1,
    null,
    4900,
    '00000000-0000-4000-8000-000000000501/00000000-0000-4000-8000-000000000511/receipt.jpg',
    null
  ),
  'validation_failed',
  'reference values containing non-digit separators are rejected'
);

select is(
  public.submit_premium_payment(
    '00000000-0000-4000-8000-000000000501',
    '00000000-0000-4000-8000-000000000512',
    '1234567890131',
    current_date - 1,
    null,
    4901,
    '00000000-0000-4000-8000-000000000501/00000000-0000-4000-8000-000000000512/receipt.jpg',
    null
  ),
  'validation_failed',
  'a manually entered amount must match the configured plan amount'
);

select is(
  public.submit_premium_payment(
    '00000000-0000-4000-8000-000000000501',
    '00000000-0000-4000-8000-000000000513',
    '1234567890132',
    current_date + 1,
    null,
    4900,
    '00000000-0000-4000-8000-000000000501/00000000-0000-4000-8000-000000000513/receipt.jpg',
    null
  ),
  'validation_failed',
  'future transaction dates are rejected'
);

select is(
  public.submit_premium_payment(
    '00000000-0000-4000-8000-000000000501',
    '00000000-0000-4000-8000-000000000516',
    '1234567890133',
    current_date - 1,
    null,
    4900,
    null,
    null
  ),
  'validation_failed',
  'a receipt storage path is required'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
values (
  '00000000-0000-4000-8000-000000000514',
  'authenticated',
  'authenticated',
  'payment-manual-review-second-test@example.com',
  '',
  now(),
  '{}'::jsonb,
  '{}'::jsonb
);

insert into public.premium_payment_requests (
  id, user_id, plan_id, amount_centavos, currency,
  unique_payment_reference, payment_status, customer_email
)
values (
  '00000000-0000-4000-8000-000000000515',
  '00000000-0000-4000-8000-000000000514',
  (select id from public.payment_plans where code = 'premium_30_days'),
  4900,
  'PHP',
  'LUM-PGTEST-CROSS-ACCOUNT-DUPLICATE-001',
  'pending',
  'payment-manual-review-second-test@example.com'
);

select is(
  public.submit_premium_payment(
    '00000000-0000-4000-8000-000000000514',
    '00000000-0000-4000-8000-000000000515',
    '1234567890130',
    current_date - 1,
    null,
    4900,
    '00000000-0000-4000-8000-000000000514/00000000-0000-4000-8000-000000000515/receipt.jpg',
    null
  ),
  'duplicate_reference',
  'a reference number cannot be reused by another account'
);

select * from finish();

rollback;
