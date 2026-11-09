create or replace function public.is_verified_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from auth.users
    where id = (select auth.uid())
      and email_confirmed_at is not null
  );
$$;

revoke all on function public.is_verified_user() from public, anon;
grant execute on function public.is_verified_user() to authenticated;

drop policy if exists "Verified users manage their own profile"
  on public.profiles;
create policy "Verified users manage their own profile"
  on public.profiles for all to authenticated
  using (
    id = (select auth.uid())
    and (select public.is_verified_user())
  )
  with check (
    id = (select auth.uid())
    and (select public.is_verified_user())
  );

drop policy if exists "Verified users read their own profile photos"
  on storage.objects;
create policy "Verified users read their own profile photos"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (storage.foldername(name))[2] = 'profile'
    and (select public.is_verified_user())
  );

drop policy if exists "Verified users upload their own profile photos"
  on storage.objects;
create policy "Verified users upload their own profile photos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (storage.foldername(name))[2] = 'profile'
    and (select public.is_verified_user())
  );

drop policy if exists "Verified users delete their own profile photos"
  on storage.objects;
create policy "Verified users delete their own profile photos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (storage.foldername(name))[2] = 'profile'
    and (select public.is_verified_user())
  );
