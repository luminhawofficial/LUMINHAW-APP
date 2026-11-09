create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.plants (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  common_name text not null,
  scientific_name text,
  family text,
  category text,
  image_path text,
  created_at timestamptz not null default now(),
  unique (owner_id, common_name),
  unique (id, owner_id)
);

create table public.plant_identifications (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  plant_id uuid,
  image_path text not null,
  status text not null default 'pending'
    check (status in ('pending', 'completed', 'failed')),
  provider text,
  result jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  foreign key (plant_id, owner_id)
    references public.plants (id, owner_id) on delete cascade
);

create table public.plant_health_assessments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  plant_id uuid,
  image_path text not null,
  status text not null default 'pending'
    check (status in ('pending', 'completed', 'failed')),
  provider text,
  result jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  foreign key (plant_id, owner_id)
    references public.plants (id, owner_id) on delete cascade
);

create table public.growth_entries (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  plant_id uuid not null,
  observed_on date not null default current_date,
  height_cm numeric(8, 2) check (height_cm is null or height_cm >= 0),
  leaf_count integer check (leaf_count is null or leaf_count >= 0),
  notes text not null default '',
  image_path text,
  created_at timestamptz not null default now(),
  foreign key (plant_id, owner_id)
    references public.plants (id, owner_id) on delete cascade
);

create table public.care_activities (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  plant_id uuid not null,
  activity text not null
    check (activity in ('watered', 'fertilized', 'pruned', 'repotted', 'other')),
  notes text not null default '',
  occurred_at timestamptz not null default now(),
  foreign key (plant_id, owner_id)
    references public.plants (id, owner_id) on delete cascade
);

create index plants_owner_created_idx
  on public.plants (owner_id, created_at desc);
create index identifications_owner_created_idx
  on public.plant_identifications (owner_id, created_at desc);
create index health_assessments_owner_created_idx
  on public.plant_health_assessments (owner_id, created_at desc);
create index growth_entries_owner_plant_date_idx
  on public.growth_entries (owner_id, plant_id, observed_on desc);
create index care_activities_owner_plant_date_idx
  on public.care_activities (owner_id, plant_id, occurred_at desc);

alter table public.profiles enable row level security;
alter table public.plants enable row level security;
alter table public.plant_identifications enable row level security;
alter table public.plant_health_assessments enable row level security;
alter table public.growth_entries enable row level security;
alter table public.care_activities enable row level security;

create policy "Users manage their own profile"
  on public.profiles for all to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy "Users manage their own plants"
  on public.plants for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy "Users manage their own identifications"
  on public.plant_identifications for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy "Users manage their own health assessments"
  on public.plant_health_assessments for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy "Users manage their own growth entries"
  on public.growth_entries for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy "Users manage their own care activities"
  on public.care_activities for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', '')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'plant-photos',
  'plant-photos',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

create policy "Users read their own plant photos"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Users upload their own plant photos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Users update their own plant photos"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Users delete their own plant photos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
