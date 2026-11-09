create extension if not exists pgcrypto;

create table if not exists public.plant_catalog (
  id uuid primary key default gen_random_uuid(),
  gbif_key bigint unique,
  scientific_name text not null,
  common_name text,
  family text,
  genus text,
  description text,
  description_source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists plant_catalog_scientific_idx
  on public.plant_catalog (lower(scientific_name));
create index if not exists plant_catalog_common_idx
  on public.plant_catalog (lower(common_name));

create table if not exists public.plant_care (
  plant_id uuid primary key references public.plant_catalog(id) on delete cascade,
  watering text,
  sunlight text,
  soil text,
  temperature text,
  instructions text,
  source_url text,
  reviewed boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.plant_images (
  id uuid primary key default gen_random_uuid(),
  plant_id uuid not null references public.plant_catalog(id) on delete cascade,
  image_url text not null,
  creator text,
  source_url text,
  license text,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  unique (plant_id, image_url)
);

create index if not exists plant_images_plant_idx
  on public.plant_images (plant_id);

alter table public.plant_catalog enable row level security;
alter table public.plant_care enable row level security;
alter table public.plant_images enable row level security;

revoke all on public.plant_catalog, public.plant_care, public.plant_images
  from public, anon, authenticated;
grant all on public.plant_catalog, public.plant_care, public.plant_images
  to service_role;
