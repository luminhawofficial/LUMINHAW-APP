begin;

select plan(19);

select ok(
  not has_table_privilege('anon', 'public.admin_roles', 'SELECT')
  and not has_table_privilege('authenticated', 'public.admin_roles', 'SELECT'),
  'browser roles cannot read administrator assignments'
);

select ok(
  not has_table_privilege('authenticated', 'public.admin_activity_logs', 'SELECT')
  and not has_table_privilege('authenticated', 'public.admin_activity_logs', 'INSERT'),
  'browser roles cannot access administrator audit records'
);

select ok(
  has_table_privilege('service_role', 'public.admin_roles', 'SELECT')
  and has_table_privilege('service_role', 'public.admin_activity_logs', 'INSERT'),
  'trusted server role can access administrator records'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_set_role(uuid, uuid, text, text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.admin_set_role(uuid, uuid, text, text)',
    'EXECUTE'
  ),
  'browser roles cannot assign administrator roles'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.admin_set_role(uuid, uuid, text, text)',
    'EXECUTE'
  ),
  'trusted server role can call the role assignment function'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.admin_dashboard_summary(uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.admin_dashboard_summary(uuid)',
    'EXECUTE'
  ),
  'dashboard summary is restricted to the trusted server role'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.admin_list_users(uuid, text, integer, integer)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.admin_list_users(uuid, text, integer, integer)',
    'EXECUTE'
  ),
  'administrator user search is restricted to the trusted server role'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_review_premium_payment(uuid, uuid, text, boolean, text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.admin_review_premium_payment(uuid, uuid, text, boolean, text)',
    'EXECUTE'
  ),
  'browser roles cannot approve or reject payments directly'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.admin_review_premium_payment(uuid, uuid, text, boolean, text)',
    'EXECUTE'
  ),
  'trusted server role can call the guarded payment review function'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.review_premium_payment_by_email_token(text, text, boolean, text)',
    'EXECUTE'
  ),
  'existing email-token payment review remains available'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.review_premium_payment(uuid, uuid, text, text)',
    'EXECUTE'
  ),
  'disabled legacy payment review remains unavailable'
);

select ok(
  exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'admin_roles'
      and c.relrowsecurity
  ),
  'administrator assignments have row level security enabled'
);

select ok(
  exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'admin_activity_logs'
      and c.relrowsecurity
  ),
  'administrator audit records have row level security enabled'
);

select ok(
  position('final active Admin' in pg_get_functiondef(
    'public.admin_set_role(uuid, uuid, text, text)'::regprocedure
  )) > 0,
  'role assignment protects the final active Admin'
);

select ok(
  position('cannot approve their own payment' in pg_get_functiondef(
    'public.admin_review_premium_payment(uuid, uuid, text, boolean, text)'::regprocedure
  )) > 0,
  'payment approval prevents an administrator approving their own payment'
);

select ok(
  position('role = ''admin''' in pg_get_functiondef(
    'public.admin_review_premium_payment(uuid, uuid, text, boolean, text)'::regprocedure
  )) > 0
  and position('status = ''active''' in pg_get_functiondef(
    'public.admin_review_premium_payment(uuid, uuid, text, boolean, text)'::regprocedure
  )) > 0
  and position('role = ''super_admin''' in pg_get_functiondef(
    'public.admin_review_premium_payment(uuid, uuid, text, boolean, text)'::regprocedure
  )) = 0,
  'only active Admins can review payments'
);

select ok(
  position('role = ''admin''' in pg_get_functiondef(
    'public.admin_set_role(uuid, uuid, text, text)'::regprocedure
  )) > 0
  and position('role = ''super_admin''' in pg_get_functiondef(
    'public.admin_set_role(uuid, uuid, text, text)'::regprocedure
  )) = 0
  and position('Only one active Admin account is allowed.' in pg_get_functiondef(
    'public.admin_set_role(uuid, uuid, text, text)'::regprocedure
  )) > 0,
  'role management is Admin-only and enforces a single active Admin'
);

select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'admin_roles_one_active_admin_idx'
      and indexdef ilike '%unique%'
      and indexdef ilike '%role%'
      and indexdef ilike '%active%'
  ),
  'a unique index enforces at most one active Admin'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.admin_roles'::regclass
      and conname = 'admin_roles_role_check'
      and pg_get_constraintdef(oid) not ilike '%super_admin%'
  ),
  'the administrator role constraint no longer permits Super Admin'
);

select * from finish();

rollback;
