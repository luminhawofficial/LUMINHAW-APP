create table if not exists public.plant_provider_cache (
  id uuid primary key default gen_random_uuid(),
  provider text not null
    check (provider in ('gbif', 'perenual', 'plant_id', 'plantnet')),
  lookup_key text not null,
  response jsonb not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (provider, lookup_key)
);

create index if not exists plant_provider_cache_expiry_idx
  on public.plant_provider_cache (expires_at);

alter table public.plant_provider_cache enable row level security;
revoke all on public.plant_provider_cache from public, anon, authenticated;
grant all on public.plant_provider_cache to service_role;
