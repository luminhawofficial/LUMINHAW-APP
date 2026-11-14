create or replace function public.sync_plant_catalog_search_aliases()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if not new.is_verified or not new.is_active then
    return new;
  end if;

  insert into public.plant_catalog_aliases (
    plant_id,
    alias_name,
    common_name,
    scientific_name,
    local_name,
    language,
    region
  )
  select
    new.id,
    names.alias_name,
    coalesce(new.common_name, new.scientific_name),
    new.scientific_name,
    names.local_name,
    names.language,
    names.region
  from (
    values
      (nullif(btrim(new.common_name), ''), null::text, 'und', 'Global'),
      (nullif(btrim(new.scientific_name), ''), null::text, 'la', 'Global'),
      (nullif(btrim(new.english_name), ''), null::text, 'en', 'Global'),
      (
        nullif(btrim(new.tagalog_name), ''),
        nullif(btrim(new.tagalog_name), ''),
        'fil',
        'Philippines'
      ),
      (
        nullif(btrim(new.bisaya_name), ''),
        nullif(btrim(new.bisaya_name), ''),
        'ceb',
        'Visayas'
      )
  ) as names(alias_name, local_name, language, region)
  where names.alias_name is not null
  on conflict (plant_id, normalized_alias, language, region) do update
  set common_name = excluded.common_name,
      scientific_name = excluded.scientific_name,
      local_name = excluded.local_name;

  return new;
end;
$function$;

revoke all on function public.sync_plant_catalog_search_aliases()
  from public, anon, authenticated;
grant execute on function public.sync_plant_catalog_search_aliases()
  to service_role;

drop trigger if exists plant_catalog_search_alias_sync
  on public.plant_catalog;
create trigger plant_catalog_search_alias_sync
after insert or update of
  common_name,
  scientific_name,
  english_name,
  tagalog_name,
  bisaya_name,
  is_verified,
  is_active
on public.plant_catalog
for each row
execute function public.sync_plant_catalog_search_aliases();

insert into public.plant_catalog_aliases (
  plant_id,
  alias_name,
  common_name,
  scientific_name,
  local_name,
  language,
  region
)
select
  plant.id,
  names.alias_name,
  coalesce(plant.common_name, plant.scientific_name),
  plant.scientific_name,
  names.local_name,
  names.language,
  names.region
from public.plant_catalog as plant
cross join lateral (
  values
    (nullif(btrim(plant.common_name), ''), null::text, 'und', 'Global'),
    (nullif(btrim(plant.scientific_name), ''), null::text, 'la', 'Global'),
    (nullif(btrim(plant.english_name), ''), null::text, 'en', 'Global'),
    (
      nullif(btrim(plant.tagalog_name), ''),
      nullif(btrim(plant.tagalog_name), ''),
      'fil',
      'Philippines'
    ),
    (
      nullif(btrim(plant.bisaya_name), ''),
      nullif(btrim(plant.bisaya_name), ''),
      'ceb',
      'Visayas'
    )
) as names(alias_name, local_name, language, region)
where plant.is_verified
  and plant.is_active
  and names.alias_name is not null
  and length(btrim(names.alias_name)) between 1 and 200
on conflict (plant_id, normalized_alias, language, region) do update
set common_name = excluded.common_name,
    scientific_name = excluded.scientific_name,
    local_name = excluded.local_name;
