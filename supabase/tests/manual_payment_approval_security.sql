begin;

select plan(11);

select ok(
  not has_function_privilege(
    'anon',
    'public.review_premium_payment(uuid, uuid, text, text)',
    'EXECUTE'
  ),
  'anon cannot execute payment approval'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.review_premium_payment(uuid, uuid, text, text)',
    'EXECUTE'
  ),
  'authenticated users cannot execute payment approval'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.admin_manage_premium_entitlement(uuid, uuid, text, text, integer, text)',
    'EXECUTE'
  ),
  'authenticated users cannot call the administrative entitlement RPC'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.review_premium_payment(uuid, uuid, text, text)',
    'EXECUTE'
  ),
  'service_role cannot directly invoke legacy payment review'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.review_premium_payment_by_email_token(text, text, boolean, text)',
    'EXECUTE'
  ),
  'trusted service_role can process email-token payment review'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.review_premium_payment_by_email_token(text, text, boolean, text)',
    'EXECUTE'
  ),
  'anonymous users cannot invoke email-token payment review'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.review_premium_payment_by_email_token(text, text, boolean, text)',
    'EXECUTE'
  ),
  'authenticated users cannot invoke email-token payment review directly'
);

select ok(
  not has_table_privilege('authenticated', 'public.payment_admins', 'SELECT'),
  'authenticated users cannot read administrator assignments'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.subscription_entitlements',
    'INSERT'
  ),
  'authenticated users cannot insert Premium entitlements'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.subscription_entitlements',
    'UPDATE'
  ),
  'authenticated users cannot update Premium entitlements'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.subscription_entitlements',
    'DELETE'
  ),
  'authenticated users cannot delete Premium entitlements'
);

select * from finish();

rollback;
