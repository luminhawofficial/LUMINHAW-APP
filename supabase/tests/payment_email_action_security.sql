begin;

select plan(36);

select ok(
  to_regprocedure(
    'public.replace_payment_email_action_tokens(uuid, uuid, text, text, timestamptz)'
  ) is not null,
  'payment email token replacement RPC exists'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.replace_payment_email_action_tokens(uuid, uuid, text, text, timestamptz)',
    'EXECUTE'
  ),
  'anon cannot replace payment email action tokens'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.replace_payment_email_action_tokens(uuid, uuid, text, text, timestamptz)',
    'EXECUTE'
  ),
  'authenticated users cannot replace payment email action tokens'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.replace_payment_email_action_tokens(uuid, uuid, text, text, timestamptz)',
    'EXECUTE'
  ),
  'only the trusted service role can replace payment email action tokens'
);

select ok(
  (
    select prosecdef
    from pg_proc
    where oid = to_regprocedure(
      'public.replace_payment_email_action_tokens(uuid, uuid, text, text, timestamptz)'
    )
  ),
  'token replacement executes with a constrained security-definer function'
);

select ok(
  exists (
    select 1
    from pg_index as idx
    join pg_class as relation on relation.oid = idx.indexrelid
    where relation.relname = 'payment_email_action_tokens_one_active_action_idx'
      and idx.indisunique
      and pg_get_expr(idx.indpred, idx.indrelid)
        like '%consumed_at IS NULL%'
      and pg_get_expr(idx.indpred, idx.indrelid)
        like '%revoked_at IS NULL%'
  ),
  'only one unused action token per action can remain active'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.payment_email_action_tokens'::regclass
  ),
  'payment email action tokens have row-level security enabled'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.payment_email_action_tokens',
    'SELECT'
  ),
  'authenticated users cannot read payment email action tokens'
);

select ok(
  not (
    select public
    from storage.buckets
    where id = 'premium-payment-proofs'
  ),
  'payment receipt storage remains private'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
values (
  '00000000-0000-4000-8000-000000000101',
  'authenticated',
  'authenticated',
  'payment-flow-test@example.com',
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
  '00000000-0000-4000-8000-000000000201',
  '00000000-0000-4000-8000-000000000101',
  (select id from public.payment_plans where code = 'premium_30_days'),
  4900,
  'PHP',
  'LUM-PGTEST-EMAIL-001',
  'under_review',
  'payment-flow-test@example.com'
);

insert into public.payment_email_notifications (
  id, payment_request_id, notification_type, recipient_email,
  delivery_status, attempt_count, delivery_claimed_at, delivery_claim_token
)
values (
  '00000000-0000-4000-8000-000000000301',
  '00000000-0000-4000-8000-000000000201',
  'admin_payment_submitted',
  'luminhawofficial@gmail.com',
  'sending',
  1,
  now(),
  '00000000-0000-4000-8000-000000000401'
);

select lives_ok(
  $$select public.replace_payment_email_action_tokens(
    '00000000-0000-4000-8000-000000000301',
    '00000000-0000-4000-8000-000000000401',
    repeat('a', 64),
    repeat('b', 64),
    now() + interval '24 hours'
  )$$,
  'first delivery creates an approval/rejection token pair'
);

select is(
  (
    select count(*)::integer
    from public.payment_email_action_tokens
    where payment_request_id = '00000000-0000-4000-8000-000000000201'
      and consumed_at is null
      and revoked_at is null
  ),
  2,
  'first delivery leaves one active token per action'
);

update public.payment_email_notifications
set delivery_claim_token = '00000000-0000-4000-8000-000000000402',
    delivery_claimed_at = now()
where id = '00000000-0000-4000-8000-000000000301';

select lives_ok(
  $$select public.replace_payment_email_action_tokens(
    '00000000-0000-4000-8000-000000000301',
    '00000000-0000-4000-8000-000000000402',
    repeat('c', 64),
    repeat('d', 64),
    now() + interval '24 hours'
  )$$,
  'retry atomically replaces the previous unused token pair'
);

select is(
  (
    select count(*)::integer
    from public.payment_email_action_tokens
    where payment_request_id = '00000000-0000-4000-8000-000000000201'
      and revoked_at is not null
  ),
  2,
  'retry revokes both tokens from the previous delivery'
);

select is(
  (
    select count(*)::integer
    from public.payment_email_action_tokens
    where payment_request_id = '00000000-0000-4000-8000-000000000201'
      and consumed_at is null
      and revoked_at is null
  ),
  2,
  'retry leaves only one active token pair'
);

update public.payment_email_notifications
set delivery_status = 'sent'
where id = '00000000-0000-4000-8000-000000000301';

select throws_ok(
  $$select public.replace_payment_email_action_tokens(
    '00000000-0000-4000-8000-000000000301',
    '00000000-0000-4000-8000-000000000402',
    repeat('e', 64),
    repeat('f', 64),
    now() + interval '24 hours'
  )$$,
  'P0001',
  'Payment notification claim is invalid.',
  'a delivered notification cannot rotate valid links'
);

select is(
  (
    select count(*)::integer
    from public.payment_email_action_tokens
    where payment_request_id = '00000000-0000-4000-8000-000000000201'
      and consumed_at is null
      and revoked_at is null
  ),
  2,
  'a delivered notification keeps its existing valid action links'
);

select lives_ok(
  $$select public.review_premium_payment_by_email_token(
    repeat('d', 64),
    'reject',
    false,
    'Test rejection'
  )$$,
  'a valid rejection token is consumed atomically'
);

select is(
  (
    select payment_status
    from public.premium_payment_requests
    where id = '00000000-0000-4000-8000-000000000201'
  ),
  'rejected'::text,
  'the confirmed rejection records a rejected payment'
);

select is(
  (
    select rejection_reason
    from public.premium_payment_requests
    where id = '00000000-0000-4000-8000-000000000201'
  ),
  'Test rejection'::text,
  'the confirmed rejection preserves its reason'
);

select is(
  (
    select count(*)::integer
    from public.subscription_entitlements
    where user_id = '00000000-0000-4000-8000-000000000101'
      and product_id = 'manual_gcash'
  ),
  0,
  'a rejected payment does not activate Premium'
);

select is(
  (
    select count(*)::integer
    from public.payment_email_action_tokens
    where token_hash = repeat('d', 64)
      and consumed_at is not null
  ),
  1,
  'the used token is marked consumed'
);

select throws_ok(
  $$select public.review_premium_payment_by_email_token(
    repeat('d', 64),
    'reject',
    false,
    'Replay attempt'
  )$$,
  'P0001',
  'Email payment action is invalid or expired.',
  'a consumed action token cannot be replayed'
);

insert into public.payment_email_action_tokens (
  payment_request_id, action, reviewer_email, token_hash, expires_at
)
values (
  '00000000-0000-4000-8000-000000000201',
  'approve',
  'luminhawofficial@gmail.com',
  repeat('f', 64),
  now() - interval '1 minute'
);

select throws_ok(
  $$select public.review_premium_payment_by_email_token(
    repeat('f', 64),
    'approve',
    true,
    null
  )$$,
  'P0001',
  'Email payment action is invalid or expired.',
  'an expired action token cannot approve a payment'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
values (
  '00000000-0000-4000-8000-000000000102',
  'authenticated',
  'authenticated',
  'luminhawofficial@gmail.com',
  '',
  now(),
  '{}'::jsonb,
  '{}'::jsonb
)
on conflict do nothing;

insert into public.premium_payment_requests (
  id, user_id, plan_id, amount_centavos, currency,
  unique_payment_reference, payment_status, customer_email
)
values (
  '00000000-0000-4000-8000-000000000202',
  (
    select id from auth.users
    where lower(email) = 'luminhawofficial@gmail.com'
  ),
  (select id from public.payment_plans where code = 'premium_30_days'),
  4900,
  'PHP',
  'LUM-PGTEST-EMAIL-002',
  'under_review',
  'luminhawofficial@gmail.com'
);

insert into public.payment_email_action_tokens (
  payment_request_id, action, reviewer_email, token_hash, expires_at
)
values (
  '00000000-0000-4000-8000-000000000202',
  'approve',
  'luminhawofficial@gmail.com',
  repeat('1', 64),
  now() + interval '24 hours'
);

select throws_ok(
  $$select public.review_premium_payment_by_email_token(
    repeat('1', 64),
    'approve',
    true,
    null
  )$$,
  'P0001',
  'A customer cannot approve their own payment.',
  'the reviewer cannot approve a payment submitted with their own email'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
values (
  '00000000-0000-4000-8000-000000000103',
  'authenticated',
  'authenticated',
  'payment-entitlement-test@example.com',
  '',
  now(),
  '{}'::jsonb,
  '{}'::jsonb
);

insert into public.premium_payment_requests (
  id, user_id, plan_id, amount_centavos, currency,
  unique_payment_reference, payment_status, customer_email
)
values
  (
    '00000000-0000-4000-8000-000000000203',
    '00000000-0000-4000-8000-000000000103',
    (select id from public.payment_plans where code = 'premium_30_days'),
    4900,
    'PHP',
    'LUM-PGTEST-EMAIL-003',
    'under_review',
    'payment-entitlement-test@example.com'
  ),
  (
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000103',
    (select id from public.payment_plans where code = 'premium_365_days'),
    49900,
    'PHP',
    'LUM-PGTEST-EMAIL-004',
    'under_review',
    'payment-entitlement-test@example.com'
  );

insert into public.payment_email_action_tokens (
  payment_request_id, action, reviewer_email, token_hash, expires_at
)
values
  (
    '00000000-0000-4000-8000-000000000203',
    'approve',
    'luminhawofficial@gmail.com',
    repeat('2', 64),
    now() + interval '24 hours'
  ),
  (
    '00000000-0000-4000-8000-000000000204',
    'approve',
    'luminhawofficial@gmail.com',
    repeat('3', 64),
    now() + interval '24 hours'
  );

select is(
  (
    select count(*)::integer
    from public.subscription_entitlements
    where user_id = '00000000-0000-4000-8000-000000000103'
      and product_id = 'manual_gcash'
  ),
  0,
  'a payment awaiting approval has no Premium entitlement'
);

select throws_ok(
  $$select public.review_premium_payment_by_email_token(
    repeat('2', 64),
    'approve',
    false,
    null
  )$$,
  'P0001',
  'Invalid email payment action.',
  'an approval without funds-received confirmation is rejected'
);

select is(
  (
    select count(*)::integer
    from public.payment_email_action_tokens
    where token_hash = repeat('2', 64)
      and consumed_at is null
      and revoked_at is null
  ),
  1,
  'a failed unconfirmed approval leaves its token unused'
);

select lives_ok(
  $$select public.review_premium_payment_by_email_token(
    repeat('2', 64),
    'approve',
    true,
    null
  )$$,
  'a confirmed approval activates the monthly entitlement'
);

select is(
  (
    select payment_status
    from public.premium_payment_requests
    where id = '00000000-0000-4000-8000-000000000203'
  ),
  'approved'::text,
  'the confirmed monthly payment is approved'
);

select ok(
  (
    select status = 'active'
      and expires_at between now() + interval '29 days 23 hours'
        and now() + interval '30 days 1 hour'
    from public.subscription_entitlements
    where user_id = '00000000-0000-4000-8000-000000000103'
      and product_id = 'manual_gcash'
  ),
  'monthly approval grants an active entitlement expiring after 30 days'
);

select is(
  (
    select payment.entitlement_expires_at
      = entitlement.expires_at
    from public.premium_payment_requests as payment
    join public.subscription_entitlements as entitlement
      on entitlement.user_id = payment.user_id
    where payment.id = '00000000-0000-4000-8000-000000000203'
      and entitlement.product_id = 'manual_gcash'
  ),
  true,
  'the monthly payment records the entitlement expiry'
);

select is(
  (
    select count(*)::integer
    from public.payment_email_notifications
    where payment_request_id = '00000000-0000-4000-8000-000000000203'
      and notification_type = 'customer_payment_reviewed'
  ),
  1,
  'monthly approval queues a customer status email'
);

select lives_ok(
  $$select public.review_premium_payment_by_email_token(
    repeat('3', 64),
    'approve',
    true,
    null
  )$$,
  'a second confirmed approval extends the active entitlement'
);

select is(
  (
    select entitlement.expires_at
    from public.subscription_entitlements as entitlement
    where entitlement.user_id = '00000000-0000-4000-8000-000000000103'
      and entitlement.product_id = 'manual_gcash'
  ),
  (
    select entitlement_expires_at + interval '365 days'
    from public.premium_payment_requests
    where id = '00000000-0000-4000-8000-000000000203'
  ),
  'yearly approval extends from the existing expiry by exactly 365 days'
);

select is(
  (
    select payment.entitlement_expires_at = entitlement.expires_at
    from public.premium_payment_requests as payment
    join public.subscription_entitlements as entitlement
      on entitlement.user_id = payment.user_id
    where payment.id = '00000000-0000-4000-8000-000000000204'
      and entitlement.product_id = 'manual_gcash'
  ),
  true,
  'the yearly payment records the extended entitlement expiry'
);

select is(
  (
    select count(*)::integer
    from public.premium_payment_events
    where payment_request_id in (
      '00000000-0000-4000-8000-000000000203',
      '00000000-0000-4000-8000-000000000204'
    )
      and event_type = 'email_review'
      and new_status = 'approved'
  ),
  2,
  'each email approval records an audit event'
);

select * from finish();

rollback;
