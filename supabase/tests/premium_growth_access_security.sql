begin;

select plan(2);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'growth_entries'
      and policyname = 'Premium users manage their own growth entries'
      and cmd = 'ALL'
      and qual like '%subscription_entitlements%'
      and qual like '%expires_at > now()%'
      and with_check like '%subscription_entitlements%'
      and with_check like '%expires_at > now()%'
  ),
  'growth entries require an active Premium entitlement for reads and writes'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'care_activities'
      and policyname = 'Premium users manage their own care activities'
      and cmd = 'ALL'
      and qual like '%subscription_entitlements%'
      and qual like '%expires_at > now()%'
      and with_check like '%subscription_entitlements%'
      and with_check like '%expires_at > now()%'
  ),
  'care activities require an active Premium entitlement for reads and writes'
);

select * from finish();

rollback;
