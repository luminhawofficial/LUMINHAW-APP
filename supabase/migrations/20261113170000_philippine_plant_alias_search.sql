create extension if not exists pg_trgm with schema extensions;

alter table public.plant_catalog
  add column if not exists tagalog_name text,
  add column if not exists bisaya_name text,
  add column if not exists english_name text,
  add column if not exists category text,
  add column if not exists is_verified boolean not null default false,
  add column if not exists is_active boolean not null default true,
  add column if not exists verification_status text not null default 'pending',
  add column if not exists verified_at timestamptz;

alter table public.plant_catalog
  drop constraint if exists plant_catalog_verification_status_check;
alter table public.plant_catalog
  add constraint plant_catalog_verification_status_check
  check (verification_status in ('pending', 'verified', 'rejected'));

alter table public.plant_images
  add column if not exists is_verified boolean not null default false;

create table if not exists public.plant_catalog_aliases (
  id uuid primary key default gen_random_uuid(),
  plant_id uuid not null
    references public.plant_catalog (id) on delete cascade,
  alias_name text not null check (length(btrim(alias_name)) between 1 and 200),
  common_name text not null,
  scientific_name text not null,
  local_name text,
  language text not null,
  region text not null default 'Global',
  alternative_name text,
  normalized_alias text generated always as (
    btrim(regexp_replace(
      regexp_replace(lower(alias_name), '[^[:alnum:]]+', ' ', 'g'),
      '[[:space:]]+',
      ' ',
      'g'
    ))
  ) stored,
  created_at timestamptz not null default pg_catalog.now(),
  unique (plant_id, normalized_alias, language, region)
);

create index if not exists plant_catalog_aliases_search_idx
  on public.plant_catalog_aliases
  using gin (normalized_alias extensions.gin_trgm_ops);
create index if not exists plant_catalog_aliases_plant_idx
  on public.plant_catalog_aliases (plant_id);

alter table public.plant_catalog_aliases enable row level security;
drop policy if exists "Verified plant aliases visible to signed-in users"
  on public.plant_catalog_aliases;
create policy "Verified plant aliases visible to signed-in users"
  on public.plant_catalog_aliases for select to authenticated
  using (
    exists (
      select 1
      from public.plant_catalog
      where plant_catalog.id = plant_catalog_aliases.plant_id
        and plant_catalog.is_verified
        and plant_catalog.is_active
    )
  );
revoke all on public.plant_catalog_aliases from public, anon, authenticated;
grant select on public.plant_catalog_aliases to authenticated;
grant all on public.plant_catalog_aliases to service_role;

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
select *
from (values
  (
    2928525, 'Ipomoea aquatica', 'Kangkong', 'Water spinach',
    'Convolvulaceae', 'Ipomoea',
    'A tropical aquatic vine cultivated for its edible leaves and tender shoots.',
    'LUMINHAW Philippine plant-name starter catalog',
    'Kangkong', 'Kangkong', 'Vegetable',
    true, true, 'verified', pg_catalog.now()
  ),
  (
    3054181, 'Moringa oleifera', 'Malunggay', 'Moringa',
    'Moringaceae', 'Moringa',
    'A tropical tree widely grown for its edible leaves and seed pods.',
    'LUMINHAW Philippine plant-name starter catalog',
    'Malunggay', 'Kamunggay', 'Edible tree',
    true, true, 'verified', pg_catalog.now()
  ),
  (
    2874581, 'Momordica charantia', 'Ampalaya', 'Bitter gourd',
    'Cucurbitaceae', 'Momordica',
    'A tropical climbing vine grown for its distinctive bitter edible fruit.',
    'LUMINHAW Philippine plant-name starter catalog',
    'Ampalaya', 'Ampalaya', 'Vegetable',
    true, true, 'verified', pg_catalog.now()
  ),
  (
    2928551, 'Ipomoea batatas', 'Kamote', 'Sweet potato',
    'Convolvulaceae', 'Ipomoea',
    'A trailing tropical vine cultivated for its edible storage roots and leaves.',
    'LUMINHAW Philippine plant-name starter catalog',
    'Kamote', 'Kamote', 'Root crop',
    true, true, 'verified', pg_catalog.now()
  ),
  (
    2762752, 'Musa × paradisiaca', 'Saging', 'Banana',
    'Musaceae', 'Musa',
    'A cultivated tropical banana plant grown for its edible fruit.',
    'LUMINHAW Philippine plant-name starter catalog',
    'Saging', 'Saging', 'Fruit',
    true, true, 'verified', pg_catalog.now()
  ),
  (
    2930617, 'Solanum melongena', 'Talong', 'Eggplant',
    'Solanaceae', 'Solanum',
    'A warm-season crop cultivated for its edible fruit.',
    'LUMINHAW Philippine plant-name starter catalog',
    'Talong', 'Talong', 'Vegetable',
    true, true, 'verified', pg_catalog.now()
  ),
  (
    2930137, 'Solanum lycopersicum', 'Kamatis', 'Tomato',
    'Solanaceae', 'Solanum',
    'A widely cultivated crop grown for its edible fruit.',
    'LUMINHAW Philippine plant-name starter catalog',
    'Kamatis', 'Kamatis', 'Vegetable',
    true, true, 'verified', pg_catalog.now()
  ),
  (
    7903057, 'Brassica rapa', 'Pechay', 'Bok choy',
    'Brassicaceae', 'Brassica',
    'A leafy vegetable crop in the Brassica rapa group, including bok choy.',
    'LUMINHAW Philippine plant-name starter catalog',
    'Pechay', 'Pechay', 'Leafy vegetable',
    true, true, 'verified', pg_catalog.now()
  )
) as seed (
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
where not exists (
  select 1
  from public.plant_catalog as existing
  where lower(existing.scientific_name) = lower(seed.scientific_name)
)
on conflict (gbif_key) do update
set scientific_name = excluded.scientific_name,
    common_name = excluded.common_name,
    english_name = excluded.english_name,
    family = excluded.family,
    genus = excluded.genus,
    description = excluded.description,
    description_source = excluded.description_source,
    tagalog_name = excluded.tagalog_name,
    bisaya_name = excluded.bisaya_name,
    category = excluded.category,
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
    ('Ipomoea aquatica', 'Kangkong', 'fil', 'Philippines', 'Kangkong', null),
    ('Ipomoea aquatica', 'Kangkong', 'ceb', 'Visayas', 'Kangkong', null),
    ('Ipomoea aquatica', 'Water spinach', 'en', 'Global', null, 'Water spinach'),
    ('Ipomoea aquatica', 'Chinese water spinach', 'en', 'Global', null, 'Chinese water spinach'),
    ('Ipomoea aquatica', 'Ipomoea aquatica', 'la', 'Global', null, null),
    ('Moringa oleifera', 'Malunggay', 'fil', 'Philippines', 'Malunggay', null),
    ('Moringa oleifera', 'Kamunggay', 'ceb', 'Visayas', 'Kamunggay', null),
    ('Moringa oleifera', 'Moringa', 'en', 'Global', null, 'Moringa'),
    ('Moringa oleifera', 'Drumstick tree', 'en', 'Global', null, 'Drumstick tree'),
    ('Moringa oleifera', 'Horseradish tree', 'en', 'Global', null, 'Horseradish tree'),
    ('Moringa oleifera', 'Moringa oleifera', 'la', 'Global', null, null),
    ('Momordica charantia', 'Ampalaya', 'fil', 'Philippines', 'Ampalaya', null),
    ('Momordica charantia', 'Ampalaya', 'ceb', 'Visayas', 'Ampalaya', null),
    ('Momordica charantia', 'Bitter gourd', 'en', 'Global', null, 'Bitter gourd'),
    ('Momordica charantia', 'Bitter melon', 'en', 'Global', null, 'Bitter melon'),
    ('Momordica charantia', 'Momordica charantia', 'la', 'Global', null, null),
    ('Ipomoea batatas', 'Kamote', 'fil', 'Philippines', 'Kamote', null),
    ('Ipomoea batatas', 'Kamote', 'ceb', 'Visayas', 'Kamote', null),
    ('Ipomoea batatas', 'Sweet potato', 'en', 'Global', null, 'Sweet potato'),
    ('Ipomoea batatas', 'Camote', 'en', 'Philippines', null, 'Camote'),
    ('Ipomoea batatas', 'Ipomoea batatas', 'la', 'Global', null, null),
    ('Musa × paradisiaca', 'Saging', 'fil', 'Philippines', 'Saging', null),
    ('Musa × paradisiaca', 'Saging', 'ceb', 'Visayas', 'Saging', null),
    ('Musa × paradisiaca', 'Banana', 'en', 'Global', null, 'Banana'),
    ('Musa × paradisiaca', 'Musa × paradisiaca', 'la', 'Global', null, null),
    ('Solanum melongena', 'Talong', 'fil', 'Philippines', 'Talong', null),
    ('Solanum melongena', 'Talong', 'ceb', 'Visayas', 'Talong', null),
    ('Solanum melongena', 'Eggplant', 'en', 'Global', null, 'Eggplant'),
    ('Solanum melongena', 'Aubergine', 'en', 'Global', null, 'Aubergine'),
    ('Solanum melongena', 'Solanum melongena', 'la', 'Global', null, null),
    ('Solanum lycopersicum', 'Kamatis', 'fil', 'Philippines', 'Kamatis', null),
    ('Solanum lycopersicum', 'Kamatis', 'ceb', 'Visayas', 'Kamatis', null),
    ('Solanum lycopersicum', 'Tomato', 'en', 'Global', null, 'Tomato'),
    ('Solanum lycopersicum', 'Solanum lycopersicum', 'la', 'Global', null, null),
    ('Brassica rapa', 'Pechay', 'fil', 'Philippines', 'Pechay', null),
    ('Brassica rapa', 'Pechay', 'ceb', 'Visayas', 'Pechay', null),
    ('Brassica rapa', 'Bok choy', 'en', 'Global', null, 'Bok choy'),
    ('Brassica rapa', 'Pak choi', 'en', 'Global', null, 'Pak choi'),
    ('Brassica rapa', 'Brassica rapa', 'la', 'Global', null, null)
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

insert into public.plant_catalog_aliases (
  plant_id,
  alias_name,
  common_name,
  scientific_name,
  language,
  region
)
select
  plant.id,
  name.alias_name,
  plant.common_name,
  plant.scientific_name,
  name.language,
  'Global'
from public.plant_catalog as plant
cross join lateral (
  values
    (plant.common_name, 'und'::text),
    (plant.english_name, 'en'::text),
    (plant.scientific_name, 'la'::text),
    (plant.tagalog_name, 'fil'::text),
    (plant.bisaya_name, 'ceb'::text)
) as name(alias_name, language)
where plant.is_verified
  and plant.is_active
  and name.alias_name is not null
  and btrim(name.alias_name) <> ''
on conflict (plant_id, normalized_alias, language, region) do nothing;

create or replace function public.search_plant_catalog(
  p_query text,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  plant_id uuid,
  matched_name text,
  relevance real,
  alternative_names text[],
  plant jsonb,
  has_more boolean
)
language sql
stable
security definer
set search_path = public, extensions
set pg_trgm.similarity_threshold = '0.42'
as $$
  with query_value as (
    select btrim(regexp_replace(
      regexp_replace(
        lower(btrim(coalesce(p_query, ''))),
        '[^[:alnum:]]+',
        ' ',
        'g'
      ),
      '[[:space:]]+',
      ' ',
      'g'
    )) as value
  ),
  matches as (
    select
      alias.plant_id,
      alias.alias_name as matched_name,
      case
        when alias.normalized_alias = query.value then 1000::real
        when left(alias.normalized_alias, length(query.value)) = query.value
          then 800::real
        when position(query.value in alias.normalized_alias) > 0 then 700::real
        else 500::real + extensions.similarity(
          alias.normalized_alias,
          query.value
        )
      end as score
    from public.plant_catalog_aliases as alias
    join public.plant_catalog as plant on plant.id = alias.plant_id
    cross join query_value as query
    where plant.is_verified
      and plant.is_active
      and query.value <> ''
      and (
        alias.normalized_alias = query.value
        or alias.normalized_alias like query.value || '%'
        or position(query.value in alias.normalized_alias) > 0
        or (
          length(query.value) >= 4
          and alias.normalized_alias % query.value
        )
      )
  ),
  best_match as (
    select distinct on (matches.plant_id)
      matches.plant_id,
      matches.matched_name,
      matches.score
    from matches
    order by matches.plant_id, matches.score desc, matches.matched_name
  ),
  ordered as (
    select
      best.plant_id,
      best.matched_name,
      best.score,
      plant.common_name
    from best_match as best
    join public.plant_catalog as plant on plant.id = best.plant_id
    order by best.score desc, lower(plant.common_name), best.plant_id
    limit greatest(1, least(coalesce(p_limit, 20), 50)) + 1
    offset greatest(0, least(coalesce(p_offset, 0), 500))
  ),
  page as (
    select ordered.*, row_number() over (
      order by ordered.score desc, lower(ordered.common_name), ordered.plant_id
    ) as position
    from ordered
  )
  select
    page.plant_id,
    page.matched_name,
    page.score,
    (
      select array_agg(distinct alias.alias_name order by alias.alias_name)
      from public.plant_catalog_aliases as alias
      where alias.plant_id = page.plant_id
    ) as alternative_names,
    jsonb_build_object(
      'id', plant.id,
      'gbif_key', plant.gbif_key,
      'scientific_name', plant.scientific_name,
      'common_name', plant.common_name,
      'english_name', plant.english_name,
      'family', plant.family,
      'genus', plant.genus,
      'description', plant.description,
      'description_source', plant.description_source,
      'tagalog_name', plant.tagalog_name,
      'bisaya_name', plant.bisaya_name,
      'category', plant.category,
      'is_verified', plant.is_verified,
      'is_active', plant.is_active,
      'plant_care', (
        select to_jsonb(care)
        from public.plant_care as care
        where care.plant_id = plant.id
          and care.reviewed
        limit 1
      ),
      'plant_images', coalesce((
        select jsonb_agg(to_jsonb(image))
        from public.plant_images as image
        where image.plant_id = plant.id
          and image.is_verified
      ), '[]'::jsonb)
    ) as plant,
    (select count(*) > greatest(1, least(coalesce(p_limit, 20), 50))
      from ordered) as has_more
  from page
  join public.plant_catalog as plant on plant.id = page.plant_id
  where page.position <= greatest(1, least(coalesce(p_limit, 20), 50))
  order by page.score desc, lower(plant.common_name), page.plant_id;
$$;

revoke all on function public.search_plant_catalog(text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.search_plant_catalog(text, integer, integer)
  to service_role;
