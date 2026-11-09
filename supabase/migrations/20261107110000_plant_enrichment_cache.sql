alter table public.plant_provider_cache
  drop constraint if exists plant_provider_cache_provider_check;

alter table public.plant_provider_cache
  add constraint plant_provider_cache_provider_check
  check (provider in (
    'gbif',
    'perenual',
    'plant_id',
    'plantnet',
    'plant_enrichment'
  ));
