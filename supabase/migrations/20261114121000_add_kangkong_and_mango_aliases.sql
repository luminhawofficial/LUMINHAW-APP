insert into public.plant_catalog (
  gbif_key,
  scientific_name,
  common_name,
  english_name,
  family,
  genus,
  description,
  description_source,
  tagalog_name,
  bisaya_name,
  category,
  is_verified,
  is_active,
  verification_status,
  verified_at
)
values (
  3190638,
  'Mangifera indica',
  'Mangga',
  'Mango',
  'Anacardiaceae',
  'Mangifera',
  'A tropical fruit tree widely cultivated in the Philippines for its mango fruit.',
  'LUMINHAW Philippine plant-name starter catalog; GBIF accepted taxon 3190638',
  'Mangga',
  'Mangga',
  'Fruit',
  true,
  true,
  'verified',
  pg_catalog.now()
)
on conflict (gbif_key) do update
set scientific_name = excluded.scientific_name,
    common_name = coalesce(
      nullif(btrim(public.plant_catalog.common_name), ''),
      excluded.common_name
    ),
    english_name = coalesce(
      nullif(btrim(public.plant_catalog.english_name), ''),
      excluded.english_name
    ),
    family = coalesce(public.plant_catalog.family, excluded.family),
    genus = coalesce(public.plant_catalog.genus, excluded.genus),
    description = coalesce(
      public.plant_catalog.description,
      excluded.description
    ),
    description_source = coalesce(
      public.plant_catalog.description_source,
      excluded.description_source
    ),
    tagalog_name = coalesce(
      public.plant_catalog.tagalog_name,
      excluded.tagalog_name
    ),
    bisaya_name = coalesce(
      public.plant_catalog.bisaya_name,
      excluded.bisaya_name
    ),
    category = coalesce(public.plant_catalog.category, excluded.category),
    is_verified = true,
    is_active = true,
    verification_status = 'verified',
    verified_at = coalesce(
      public.plant_catalog.verified_at,
      excluded.verified_at
    ),
    updated_at = pg_catalog.now();

with alias_seed (
  scientific_name,
  alias_name,
  language,
  region,
  local_name,
  alternative_name
) as (
  values
    ('Ipomoea aquatica', 'Kang Kong', 'fil', 'Philippines', 'Kangkong', null),
    ('Ipomoea aquatica', 'Kang Kong', 'ceb', 'Visayas', 'Kangkong', null),
    ('Mangifera indica', 'Mango', 'en', 'Global', null, 'Mango'),
    ('Mangifera indica', 'Mangga', 'fil', 'Philippines', 'Mangga', null),
    ('Mangifera indica', 'Mangga', 'ceb', 'Visayas', 'Mangga', null),
    ('Mangifera indica', 'Mangifera indica', 'la', 'Global', null, null)
)
insert into public.plant_catalog_aliases (
  plant_id,
  alias_name,
  common_name,
  scientific_name,
  local_name,
  language,
  region,
  alternative_name
)
select
  plant.id,
  seed.alias_name,
  plant.common_name,
  plant.scientific_name,
  seed.local_name,
  seed.language,
  seed.region,
  seed.alternative_name
from alias_seed as seed
join public.plant_catalog as plant
  on lower(plant.scientific_name) = lower(seed.scientific_name)
on conflict (plant_id, normalized_alias, language, region) do update
set common_name = excluded.common_name,
    scientific_name = excluded.scientific_name,
    local_name = excluded.local_name,
    alternative_name = excluded.alternative_name;
