begin;

select plan(2);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'system_announcements'
      and policyname = 'Anyone can read published system announcements'
      and cmd = 'SELECT'
      and roles @> array['anon'::name, 'authenticated'::name]
      and qual like '%is_active%'
      and qual like '%published_at <= now()%'
      and qual like '%expires_at > now()%'
  ),
  'anonymous and signed-in users can read only current announcements'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.system_announcements',
    'INSERT'
  ),
  'signed-in users cannot create or change system announcements'
);

select * from finish();

rollback;
