begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

select plan(13);

update public.plant_catalog
set field_references =
  '{"description":["https://example.com/kangkong-source"]}'::jsonb
where lower(scientific_name) = lower('Ipomoea aquatica');

select is(
  (
    select plant ->> 'common_name'
    from public.search_plant_catalog('Kangkong', 20, 0)
    order by relevance desc
    limit 1
  ),
  'Kangkong',
  'Kangkong finds the Philippine local catalog record'
);

select is(
  (
    select plant ->> 'common_name'
    from public.search_plant_catalog('Water spinach', 20, 0)
    order by relevance desc
    limit 1
  ),
  'Kangkong',
  'Water spinach resolves to Kangkong'
);

select is(
  (
    select plant ->> 'common_name'
    from public.search_plant_catalog('Ipomoea aquatica', 20, 0)
    order by relevance desc
    limit 1
  ),
  'Kangkong',
  'the scientific name resolves to Kangkong'
);

select is(
  (
    select plant ->> 'common_name'
    from public.search_plant_catalog('Malunggay', 20, 0)
    order by relevance desc
    limit 1
  ),
  'Malunggay',
  'Malunggay finds the local catalog record'
);

select is(
  (
    select plant ->> 'common_name'
    from public.search_plant_catalog('Moringa', 20, 0)
    order by relevance desc
    limit 1
  ),
  'Malunggay',
  'Moringa resolves to Malunggay'
);

select is(
  (
    select plant ->> 'common_name'
    from public.search_plant_catalog('Ampalaya', 20, 0)
    order by relevance desc
    limit 1
  ),
  'Ampalaya',
  'Ampalaya finds the local catalog record'
);

select is(
  (
    select plant ->> 'common_name'
    from public.search_plant_catalog('Kamote', 20, 0)
    order by relevance desc
    limit 1
  ),
  'Kamote',
  'Kamote finds the local catalog record'
);

select is(
  (
    select plant ->> 'common_name'
    from public.search_plant_catalog('Saging', 20, 0)
    order by relevance desc
    limit 1
  ),
  'Saging',
  'Saging finds the local catalog record'
);

select is(
  (
    select plant ->> 'common_name'
    from public.search_plant_catalog('Talong', 20, 0)
    order by relevance desc
    limit 1
  ),
  'Talong',
  'Talong finds the local catalog record'
);

select is(
  (
    select plant ->> 'common_name'
    from public.search_plant_catalog('Pechay', 20, 0)
    order by relevance desc
    limit 1
  ),
  'Pechay',
  'Pechay finds the local catalog record'
);

select is(
  (
    select plant ->> 'common_name'
    from public.search_plant_catalog('Kangkongg', 20, 0)
    order by relevance desc
    limit 1
  ),
  'Kangkong',
  'a one-character spelling error still finds Kangkong'
);

select is(
  (
    with matches as (
      select plant_id
      from public.search_plant_catalog('Kangkong', 20, 0)
      union all
      select plant_id
      from public.search_plant_catalog('Water spinach', 20, 0)
      union all
      select plant_id
      from public.search_plant_catalog('Ipomoea aquatica', 20, 0)
    )
    select count(distinct plant_id)::integer from matches
  ),
  1,
  'local, English, and scientific names resolve to one plant record'
);

select is(
  (
    select plant -> 'field_references' -> 'description' ->> 0
    from public.search_plant_catalog('Kangkong', 20, 0)
    order by relevance desc
    limit 1
  ),
  'https://example.com/kangkong-source',
  'search results include the catalog field references'
);

select * from finish();

rollback;
