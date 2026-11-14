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
          and extensions.similarity(
            alias.normalized_alias,
            query.value
          ) >= 0.42::real
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
      'field_references', plant.field_references,
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
