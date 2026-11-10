create table public.system_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(btrim(title)) between 1 and 120),
  body text not null check (length(btrim(body)) between 1 and 4000),
  category text not null
    check (category in ('update', 'maintenance', 'feature', 'account')),
  published_at timestamptz not null default now(),
  expires_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check (expires_at is null or expires_at > published_at)
);

create index system_announcements_published_idx
  on public.system_announcements (published_at desc)
  where is_active;

alter table public.system_announcements enable row level security;

create policy "Anyone can read published system announcements"
  on public.system_announcements for select to anon, authenticated
  using (
    is_active
    and published_at <= now()
    and (expires_at is null or expires_at > now())
  );

revoke all on public.system_announcements from public, anon, authenticated;
grant select on public.system_announcements to anon, authenticated;
grant all on public.system_announcements to service_role;
