begin;

select plan(8);

select ok(
  to_regclass('public.plant_provider_cache') is not null,
  'plant enrichment reuses the existing provider cache'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.plant_provider_cache'::regclass
  ),
  'provider cache row-level security remains enabled'
);

select ok(
  not has_table_privilege('anon', 'public.plant_provider_cache', 'SELECT'),
  'anonymous users cannot read provider cache records'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.plant_provider_cache',
    'SELECT'
  ),
  'authenticated users cannot read provider cache records directly'
);

select ok(
  has_table_privilege(
    'service_role',
    'public.plant_provider_cache',
    'SELECT,INSERT,UPDATE,DELETE'
  ),
  'only the trusted Edge Function role can manage provider cache records'
);

select lives_ok(
  $$
    alter table public.plant_provider_cache
      drop constraint if exists plant_provider_cache_provider_check
  $$,
  'the provider constraint can be safely replaced in a transaction'
);

select lives_ok(
  $$
    alter table public.plant_provider_cache
      add constraint plant_provider_cache_provider_check
      check (provider in (
        'gbif',
        'perenual',
        'plant_id',
        'plantnet',
        'plant_enrichment'
      ))
  $$,
  'the provider constraint allows cached plant enrichment profiles'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'plant_provider_cache_provider_check'
      and pg_get_constraintdef(oid) like '%plant_enrichment%'
  ),
  'the enrichment cache provider is constrained to an allowed provider'
);

select * from finish();

rollback;
