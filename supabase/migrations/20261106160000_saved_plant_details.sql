alter table public.plants
  add column if not exists catalog_details jsonb not null default '{}'::jsonb;
