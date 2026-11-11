begin;

select plan(8);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.plant_catalog'::regclass),
  'plant catalog RLS is enabled'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.plant_care'::regclass),
  'plant care RLS is enabled'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.plant_images'::regclass),
  'plant image RLS is enabled'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'plant_catalog'
      and policyname = 'Verified catalog visible to signed-in users'
      and qual like '%is_verified%'
      and qual like '%is_active%'
  ),
  'only active verified catalog records are readable'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'plant_care'
      and policyname = 'Reviewed care visible to signed-in users'
      and qual like '%reviewed%'
      and qual like '%plant_catalog%'
  ),
  'plant care is limited to reviewed records for verified plants'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'plant_images'
      and policyname = 'Verified images visible to signed-in users'
      and qual like '%is_verified%'
      and qual like '%plant_catalog%'
  ),
  'plant images are limited to verified records for verified plants'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'system_announcements'
      and policyname = 'Users can read published announcements for their audience'
      and qual like '%audience%'
      and qual like '%subscription_entitlements%'
  ),
  'announcement visibility follows backend audience entitlements'
);

select ok(
  has_column('public', 'system_announcements', 'dismissible')
    and has_column('public', 'system_announcements', 'audience')
    and has_column('public', 'plant_catalog', 'verification_status')
    and has_column('public', 'plant_catalog', 'compatible_weather'),
  'admin-managed content fields are available'
);

select * from finish();

rollback;
