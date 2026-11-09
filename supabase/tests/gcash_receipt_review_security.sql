begin;

select plan(22);

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
    'public.submit_premium_payment(uuid, uuid, text, date, time, text, jsonb)',
    'EXECUTE'
  ),
  'authenticated users cannot bypass server-side receipt validation'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.submit_premium_payment(uuid, uuid, text, date, time, text, jsonb)',
    'EXECUTE'
  ),
  'the trusted payment function can persist OCR results'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.submit_premium_payment(uuid, uuid, text, date, time, text, jsonb)',
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
    current_date,
    '09:42',
    '00000000-0000-4000-8000-000000000501/00000000-0000-4000-8000-000000000502/receipt.jpg',
    jsonb_build_object(
      'referenceNumber', '1234567890123',
      'transactionDate', current_date::text,
      'transactionTime', '9:41 AM',
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
      'dateMatch', true,
      'timeMatch', false,
      'amountMatch', true,
      'duplicateReference', false,
      'status', 'manual_review',
      'reason', 'The transaction time differs.'
    )
  ),
  'under_review',
  'a readable receipt with mismatching fields enters manual review'
);

select is(
  (
    select payment_status
    from public.premium_payment_requests
    where id = '00000000-0000-4000-8000-000000000502'
  ),
  'under_review'::text,
  'a receipt mismatch is not automatically rejected'
);

select is(
  (
    select ocr_status
    from public.premium_payment_requests
    where id = '00000000-0000-4000-8000-000000000502'
  ),
  'manual_review'::text,
  'the payment records its manual-review OCR status'
);

select is(
  (
    select count(*)::integer
    from public.payment_email_notifications
    where payment_request_id = '00000000-0000-4000-8000-000000000502'
      and notification_type = 'admin_payment_submitted'
  ),
  1,
  'a mismatching receipt queues administrator email review'
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
    current_date,
    '09:42',
    '00000000-0000-4000-8000-000000000501/00000000-0000-4000-8000-000000000505/receipt.jpg',
    jsonb_build_object(
      'referenceNumber', '1234567890125',
      'transactionDate', current_date::text,
      'transactionTime', '09:42',
      'amountCentavos', 4900,
      'transactionStatus', 'successful',
      'confidence', null,
      'imageWidth', 1080,
      'imageHeight', 1920,
      'validImage', true,
      'providerIdentification', 'ambiguous',
      'hasTransactionMarkers', true,
      'isGcashReceipt', false,
      'imageReadable', false,
      'referenceMatch', true,
      'dateMatch', true,
      'timeMatch', true,
      'amountMatch', true,
      'duplicateReference', false,
      'status', 'manual_review',
      'reason', 'The OCR provider text is ambiguous; verify the receipt manually.'
    )
  ),
  'under_review',
  'an ambiguous OCR.space provider with no confidence can only enter manual review'
);

select ok(
  (
    select ocr_confidence is null
      and ocr_status = 'manual_review'
      and image_quality_status = 'needs_manual_review'
    from public.premium_payment_requests
    where id = '00000000-0000-4000-8000-000000000505'
  ),
  'OCR.space confidence remains null and the receipt is marked for manual review'
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
    current_date,
    '09:42',
    '00000000-0000-4000-8000-000000000501/00000000-0000-4000-8000-000000000506/receipt.jpg',
    jsonb_build_object(
      'referenceNumber', '1234567890126',
      'transactionDate', current_date::text,
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
      'imageReadable', false,
      'referenceMatch', true,
      'dateMatch', true,
      'timeMatch', true,
      'amountMatch', true,
      'duplicateReference', false,
      'status', 'manual_review',
      'reason', 'OCR.space supplies no confidence; verify the receipt manually.'
    )
  ),
  'under_review',
  'a matching GCash receipt with null confidence is accepted only for manual review'
);

select ok(
  (
    select payment_status = 'under_review'
      and ocr_status = 'manual_review'
      and ocr_confidence is null
      and image_quality_status = 'needs_manual_review'
    from public.premium_payment_requests
    where id = '00000000-0000-4000-8000-000000000506'
  ),
  'null-confidence GCash submission is persisted for review without fabricating confidence'
);

select is(
  public.submit_premium_payment(
    '00000000-0000-4000-8000-000000000501',
    '00000000-0000-4000-8000-000000000507',
    '1234567890127',
    current_date,
    '09:42',
    '00000000-0000-4000-8000-000000000501/00000000-0000-4000-8000-000000000507/receipt.jpg',
    jsonb_build_object(
      'referenceNumber', '1234567890127',
      'transactionDate', current_date::text,
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
  'a matched receipt with null confidence is rejected'
);

select is(
  public.submit_premium_payment(
    '00000000-0000-4000-8000-000000000501',
    '00000000-0000-4000-8000-000000000508',
    '1234567890128',
    current_date,
    '09:42',
    '00000000-0000-4000-8000-000000000501/00000000-0000-4000-8000-000000000508/receipt.jpg',
    jsonb_build_object(
      'referenceNumber', '1234567890128',
      'transactionDate', current_date::text,
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
  'a manual-review receipt with confidence below 0.75 is rejected'
);

select is(
  public.submit_premium_payment(
    '00000000-0000-4000-8000-000000000501',
    '00000000-0000-4000-8000-000000000509',
    '1234567890129',
    current_date,
    '09:42',
    '00000000-0000-4000-8000-000000000501/00000000-0000-4000-8000-000000000509/receipt.jpg',
    jsonb_build_object(
      'referenceNumber', '1234567890129',
      'transactionDate', current_date::text,
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
  'a manual-review receipt with confidence above 1.0 is rejected'
);

select * from finish();

rollback;
