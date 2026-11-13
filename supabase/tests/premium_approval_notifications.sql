begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

select plan(5);

select has_column(
  'public',
  'subscription_entitlements',
  'plan_code',
  'approved plan is stored on the entitlement'
);

select has_column(
  'public',
  'subscription_entitlements',
  'starts_at',
  'effective subscription start is stored on the entitlement'
);

select ok(
  has_table_privilege('authenticated', 'public.user_notifications', 'SELECT')
    and not has_table_privilege(
      'authenticated',
      'public.user_notifications',
      'INSERT'
    )
    and exists (
      select 1
      from pg_class
      where oid = 'public.user_notifications'::regclass
        and relrowsecurity
    )
    and exists (
      select 1
      from pg_policies
      where schemaname = 'public'
        and tablename = 'user_notifications'
        and cmd = 'SELECT'
        and 'authenticated' = any(roles)
        and qual like '%auth.uid%'
    ),
  'users can read notifications but cannot create or alter them'
);

select ok(
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename in ('subscription_entitlements', 'user_notifications')
    group by pubname
    having count(distinct tablename) = 2
  ),
  'entitlement and notification changes are available through Realtime'
);

do $$
declare
  v_customer_id uuid := gen_random_uuid();
  v_admin_id uuid;
  v_payment_request_id uuid := gen_random_uuid();
  v_plan_id uuid;
  v_plan_code text;
  v_plan_duration integer;
  v_plan_amount integer;
  v_customer_email text;
  v_payment_reference text;
  v_unique_reference text;
  v_submission_status text;
  v_review_result jsonb;
  v_entitlement public.subscription_entitlements%rowtype;
  v_payment public.premium_payment_requests%rowtype;
  v_notification public.user_notifications%rowtype;
  v_notification_count integer;
begin
  select user_id into v_admin_id
  from public.admin_roles
  where role = 'admin' and status = 'active'
  limit 1;
  if v_admin_id is null then
    raise exception 'No active administrator is available for the test.';
  end if;

  select id, code, duration_days, amount_centavos
  into v_plan_id, v_plan_code, v_plan_duration, v_plan_amount
  from public.payment_plans
  where code = 'premium_30_days';
  if v_plan_id is null then
    raise exception 'The monthly Premium test plan is unavailable.';
  end if;

  v_customer_email := 'premium-activation-' || v_customer_id::text ||
    '@example.invalid';
  v_payment_reference := (
    1000000000000 + floor(random() * 9000000000000)::bigint
  )::text;
  v_unique_reference := 'LUM-ACTIVATION-' || v_payment_request_id::text;

  insert into auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data
  )
  values (
    v_customer_id,
    'authenticated',
    'authenticated',
    v_customer_email,
    '',
    pg_catalog.now(),
    '{}'::jsonb,
    '{}'::jsonb
  );

  insert into public.premium_payment_requests (
    id, user_id, plan_id, payment_method, amount_centavos, currency,
    unique_payment_reference, payment_status, customer_email
  )
  values (
    v_payment_request_id,
    v_customer_id,
    v_plan_id,
    'manual_gcash',
    v_plan_amount,
    'PHP',
    v_unique_reference,
    'pending',
    v_customer_email
  );

  if exists (
    select 1 from public.subscription_entitlements
    where user_id = v_customer_id and product_id = 'manual_gcash'
  ) or exists (
    select 1 from public.user_notifications
    where payment_request_id = v_payment_request_id
  ) then
    raise exception 'A pending payment created Premium access or a notification.';
  end if;

  v_submission_status := public.submit_premium_payment(
    v_customer_id,
    v_payment_request_id,
    v_payment_reference,
    (pg_catalog.now() at time zone 'Asia/Manila')::date - 1,
    null,
    v_plan_amount,
    v_customer_id::text || '/' || v_payment_request_id::text || '/receipt.jpg',
    null
  );
  if v_submission_status <> 'under_review' then
    raise exception 'The test payment did not enter manual review: %',
      v_submission_status;
  end if;

  if exists (
    select 1 from public.subscription_entitlements
    where user_id = v_customer_id and product_id = 'manual_gcash'
  ) or exists (
    select 1 from public.user_notifications
    where payment_request_id = v_payment_request_id
  ) then
    raise exception 'A payment awaiting approval created Premium access or a notification.';
  end if;

  begin
    perform public.admin_review_premium_payment(
      v_customer_id,
      v_payment_request_id,
      'approve',
      true,
      null
    );
    raise exception 'A non-administrator unexpectedly approved a payment.';
  exception
    when others then
      if sqlerrm <> 'Unauthorized or invalid payment review.' then
        raise;
      end if;
  end;

  v_review_result := public.admin_review_premium_payment(
    v_admin_id,
    v_payment_request_id,
    'approve',
    true,
    null
  );

  select * into v_entitlement
  from public.subscription_entitlements
  where user_id = v_customer_id and product_id = 'manual_gcash';
  select * into v_payment
  from public.premium_payment_requests
  where id = v_payment_request_id;
  select * into v_notification
  from public.user_notifications
  where payment_request_id = v_payment_request_id
    and notification_type = 'premium_activated';

  if v_payment.payment_status is distinct from 'approved'
    or v_payment.reviewed_by is distinct from v_admin_id
    or v_payment.reviewed_at is null
    or v_payment.transaction_received_confirmed is not true
    or v_entitlement.status is distinct from 'active'
    or v_entitlement.plan_code is distinct from v_plan_code
    or v_entitlement.starts_at is null
    or v_entitlement.expires_at is distinct from v_entitlement.starts_at
      + pg_catalog.make_interval(days => v_plan_duration)
    or v_entitlement.verified_at is distinct from v_entitlement.starts_at
    or v_review_result ->> 'payment_status' is distinct from 'approved'
    or v_notification.id is null
    or v_notification.title <>
      'Congratulations! You''re now a LUMINHAW Premium Member! 🎉'
    or v_notification.message <>
      'Your payment has been successfully verified and approved. Your LUMINHAW Premium subscription is now active!'
        || E'\n\n'
        || 'Enjoy your exclusive Premium features, advanced plant identification, plant health insights, and more. Thank you for choosing LUMINHAW!'
  then
    raise exception 'Approval did not atomically activate the expected plan and notification.';
  end if;

  begin
    perform public.admin_review_premium_payment(
      v_admin_id,
      v_payment_request_id,
      'approve',
      true,
      null
    );
    raise exception 'A duplicate payment approval unexpectedly succeeded.';
  exception
    when others then
      if sqlerrm <> 'Payment is not awaiting review.' then
        raise;
      end if;
  end;

  select count(*) into v_notification_count
  from public.user_notifications
  where payment_request_id = v_payment_request_id
    and notification_type = 'premium_activated';
  if v_notification_count <> 1 then
    raise exception 'Duplicate approval created duplicate notifications.';
  end if;
end;
$$;

select pass(
  'pending submissions stay Free; one authorized approval atomically activates the plan and creates one notification'
);

select * from finish();

rollback;
