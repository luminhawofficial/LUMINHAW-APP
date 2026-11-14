alter table public.plant_catalog
  add column if not exists date_updated date not null default current_date,
  add column if not exists field_references jsonb not null default '{}'::jsonb;

alter table public.plant_catalog
  drop constraint if exists plant_catalog_field_references_object_check;
alter table public.plant_catalog
  add constraint plant_catalog_field_references_object_check
  check (jsonb_typeof(field_references) = 'object');

alter table public.plant_care
  add column if not exists fertilizer text,
  add column if not exists growth_tips text,
  add column if not exists common_diseases text,
  add column if not exists treatment text,
  add column if not exists toxicity text not null default 'unknown';

alter table public.plant_care
  drop constraint if exists plant_care_toxicity_check;
alter table public.plant_care
  add constraint plant_care_toxicity_check
  check (toxicity in (
    'unknown',
    'safe',
    'toxic_pets',
    'toxic_humans',
    'toxic_pets_humans'
  ));

create or replace function public.admin_save_plant_catalog(
  p_actor_id uuid,
  p_plant_id uuid,
  p_catalog jsonb,
  p_care jsonb,
  p_field_references jsonb,
  p_image_url text,
  p_image_source_url text,
  p_date_updated date
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_plant_id uuid;
begin
  if not exists (
    select 1
    from public.admin_roles
    where user_id = p_actor_id
      and role = 'admin'
      and status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'Active admin role required';
  end if;

  if p_catalog is null
    or jsonb_typeof(p_catalog) <> 'object'
    or p_care is null
    or jsonb_typeof(p_care) <> 'object'
    or p_field_references is null
    or jsonb_typeof(p_field_references) <> 'object'
    or p_date_updated is null
  then
    raise exception using errcode = '22023', message = 'Invalid plant catalog payload';
  end if;

  if p_plant_id is null then
    insert into public.plant_catalog (
      common_name,
      scientific_name,
      tagalog_name,
      bisaya_name,
      description,
      field_references,
      date_updated,
      is_verified,
      is_active,
      verification_status,
      verified_at,
      updated_at
    )
    values (
      p_catalog ->> 'common_name',
      p_catalog ->> 'scientific_name',
      nullif(p_catalog ->> 'tagalog_name', ''),
      nullif(p_catalog ->> 'bisaya_name', ''),
      nullif(p_catalog ->> 'description', ''),
      p_field_references,
      p_date_updated,
      true,
      true,
      'verified',
      now(),
      now()
    )
    returning id into v_plant_id;
  else
    update public.plant_catalog
    set common_name = p_catalog ->> 'common_name',
        scientific_name = p_catalog ->> 'scientific_name',
        tagalog_name = nullif(p_catalog ->> 'tagalog_name', ''),
        bisaya_name = nullif(p_catalog ->> 'bisaya_name', ''),
        description = nullif(p_catalog ->> 'description', ''),
        field_references = p_field_references,
        date_updated = p_date_updated,
        is_verified = true,
        is_active = true,
        verification_status = 'verified',
        verified_at = now(),
        updated_at = now()
    where id = p_plant_id
    returning id into v_plant_id;

    if v_plant_id is null then
      raise exception using errcode = 'P0002', message = 'Plant not found';
    end if;
  end if;

  insert into public.plant_care (
    plant_id,
    water_requirements,
    sunlight_requirements,
    soil_requirements,
    fertilizer,
    growth_tips,
    common_diseases,
    treatment,
    toxicity,
    reviewed,
    updated_at
  )
  values (
    v_plant_id,
    nullif(p_care ->> 'water_requirements', ''),
    nullif(p_care ->> 'sunlight_requirements', ''),
    nullif(p_care ->> 'soil_requirements', ''),
    nullif(p_care ->> 'fertilizer', ''),
    nullif(p_care ->> 'growth_tips', ''),
    nullif(p_care ->> 'common_diseases', ''),
    nullif(p_care ->> 'treatment', ''),
    coalesce(nullif(p_care ->> 'toxicity', ''), 'unknown'),
    true,
    now()
  )
  on conflict (plant_id) do update
  set water_requirements = excluded.water_requirements,
      sunlight_requirements = excluded.sunlight_requirements,
      soil_requirements = excluded.soil_requirements,
      fertilizer = excluded.fertilizer,
      growth_tips = excluded.growth_tips,
      common_diseases = excluded.common_diseases,
      treatment = excluded.treatment,
      toxicity = excluded.toxicity,
      reviewed = true,
      updated_at = now();

  update public.plant_images
  set is_primary = false,
      is_verified = false
  where plant_id = v_plant_id and is_primary;

  if p_image_url is not null then
    insert into public.plant_images (
      plant_id,
      image_url,
      source_url,
      is_primary,
      is_verified
    )
    values (
      v_plant_id,
      p_image_url,
      p_image_source_url,
      true,
      true
    )
    on conflict (plant_id, image_url) do update
    set source_url = excluded.source_url,
        is_primary = true,
        is_verified = true;
  end if;

  return v_plant_id;
end;
$function$;

revoke all on function public.admin_save_plant_catalog(
  uuid,
  uuid,
  jsonb,
  jsonb,
  jsonb,
  text,
  text,
  date
) from public, anon, authenticated;
grant execute on function public.admin_save_plant_catalog(
  uuid,
  uuid,
  jsonb,
  jsonb,
  jsonb,
  text,
  text,
  date
) to service_role;
