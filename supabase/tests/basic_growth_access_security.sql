begin;

select plan(2);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'growth_entries'
      and policyname = 'Verified users manage their own growth entries'
      and cmd = 'ALL'
      and qual like '%is_verified_user%'
      and with_check like '%is_verified_user%'
  ),
  'verified users can read and write their own growth entries on Basic'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'care_activities'
      and policyname = 'Verified users manage their own care activities'
      and cmd = 'ALL'
      and qual like '%is_verified_user%'
      and with_check like '%is_verified_user%'
  ),
  'verified users can read and write their own care activities on Basic'
);

select * from finish();

rollback;
