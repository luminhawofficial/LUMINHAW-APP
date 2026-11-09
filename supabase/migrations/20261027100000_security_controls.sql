create table public.api_rate_limit_counters (
  user_id uuid not null references auth.users (id) on delete cascade,
  bucket text not null,
  window_number bigint not null,
  request_count integer not null check (request_count > 0),
  primary key (user_id, bucket, window_number)
);

alter table public.plant_identifications
  alter column image_path drop not null;

drop policy if exists "Users manage their own profile" on public.profiles;
create policy "Verified users manage their own profile"
  on public.profiles for all to authenticated
  using (
    id = (select auth.uid())
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  )
  with check (
    id = (select auth.uid())
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );

drop policy if exists "Users manage their own plants" on public.plants;
create policy "Verified users manage their own plants"
  on public.plants for all to authenticated
  using (
    owner_id = (select auth.uid())
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  )
  with check (
    owner_id = (select auth.uid())
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );

drop policy if exists "Users manage their own identifications"
  on public.plant_identifications;
create policy "Verified users manage their own identifications"
  on public.plant_identifications for all to authenticated
  using (
    owner_id = (select auth.uid())
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  )
  with check (
    owner_id = (select auth.uid())
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );

drop policy if exists "Users manage their own health assessments"
  on public.plant_health_assessments;
create policy "Verified users manage their own health assessments"
  on public.plant_health_assessments for all to authenticated
  using (
    owner_id = (select auth.uid())
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  )
  with check (
    owner_id = (select auth.uid())
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );

drop policy if exists "Users manage their own growth entries"
  on public.growth_entries;
create policy "Verified users manage their own growth entries"
  on public.growth_entries for all to authenticated
  using (
    owner_id = (select auth.uid())
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  )
  with check (
    owner_id = (select auth.uid())
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );

drop policy if exists "Users manage their own care activities"
  on public.care_activities;
create policy "Verified users manage their own care activities"
  on public.care_activities for all to authenticated
  using (
    owner_id = (select auth.uid())
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  )
  with check (
    owner_id = (select auth.uid())
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );

drop policy if exists "Users read their own plant photos"
  on storage.objects;
create policy "Verified users read their own plant photos"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );

drop policy if exists "Users upload their own plant photos"
  on storage.objects;
create policy "Verified users upload their own plant photos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );

drop policy if exists "Users update their own plant photos"
  on storage.objects;
create policy "Verified users update their own plant photos"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  )
  with check (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );

drop policy if exists "Users delete their own plant photos"
  on storage.objects;
create policy "Verified users delete their own plant photos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );

alter table public.api_rate_limit_counters enable row level security;
revoke all on public.api_rate_limit_counters from public, anon, authenticated;
grant all on public.api_rate_limit_counters to service_role;

create function public.consume_api_rate_limit(
  p_user_id uuid,
  p_bucket text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_window bigint;
  current_count integer;
begin
  if p_user_id is null
    or p_bucket is null
    or length(p_bucket) = 0
    or length(p_bucket) > 80
    or p_limit is null
    or p_limit < 1
    or p_limit > 10000
    or p_window_seconds is null
    or p_window_seconds < 1
    or p_window_seconds > 86400
  then
    raise exception 'Invalid rate limit parameters.';
  end if;

  current_window := floor(
    extract(epoch from pg_catalog.clock_timestamp()) / p_window_seconds
  )::bigint;

  delete from public.api_rate_limit_counters
  where bucket = p_bucket
    and window_number < current_window;

  insert into public.api_rate_limit_counters as counters (
    user_id,
    bucket,
    window_number,
    request_count
  )
  values (p_user_id, p_bucket, current_window, 1)
  on conflict (user_id, bucket, window_number)
  do update set request_count = counters.request_count + 1
  returning request_count into current_count;

  return current_count <= p_limit;
end;
$$;

revoke all on function public.consume_api_rate_limit(uuid, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_api_rate_limit(uuid, text, integer, integer)
  to service_role;

create table public.subscription_entitlements (
  user_id uuid not null references auth.users (id) on delete cascade,
  product_id text not null,
  status text not null check (status in ('active', 'expired', 'revoked')),
  expires_at timestamptz not null,
  verified_at timestamptz not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

alter table public.subscription_entitlements enable row level security;
create policy "Users read their own subscription entitlements"
  on public.subscription_entitlements for select to authenticated
  using (
    user_id = (select auth.uid())
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );

revoke all on public.subscription_entitlements from public, anon;
revoke insert, update, delete on public.subscription_entitlements
  from authenticated;
grant select on public.subscription_entitlements to authenticated;
grant all on public.subscription_entitlements to service_role;
