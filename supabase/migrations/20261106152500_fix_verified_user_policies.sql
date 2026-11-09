drop policy if exists "Verified users manage their own plants"
  on public.plants;
create policy "Verified users manage their own plants"
  on public.plants for all to authenticated
  using (
    owner_id = (select auth.uid())
    and (select public.is_verified_user())
  )
  with check (
    owner_id = (select auth.uid())
    and (select public.is_verified_user())
  );

drop policy if exists "Verified users manage their own identifications"
  on public.plant_identifications;
create policy "Verified users manage their own identifications"
  on public.plant_identifications for all to authenticated
  using (
    owner_id = (select auth.uid())
    and (select public.is_verified_user())
  )
  with check (
    owner_id = (select auth.uid())
    and (select public.is_verified_user())
  );

drop policy if exists "Verified users manage their own health assessments"
  on public.plant_health_assessments;
create policy "Verified users manage their own health assessments"
  on public.plant_health_assessments for all to authenticated
  using (
    owner_id = (select auth.uid())
    and (select public.is_verified_user())
  )
  with check (
    owner_id = (select auth.uid())
    and (select public.is_verified_user())
  );

drop policy if exists "Verified users manage their own growth entries"
  on public.growth_entries;
create policy "Verified users manage their own growth entries"
  on public.growth_entries for all to authenticated
  using (
    owner_id = (select auth.uid())
    and (select public.is_verified_user())
  )
  with check (
    owner_id = (select auth.uid())
    and (select public.is_verified_user())
  );

drop policy if exists "Verified users manage their own care activities"
  on public.care_activities;
create policy "Verified users manage their own care activities"
  on public.care_activities for all to authenticated
  using (
    owner_id = (select auth.uid())
    and (select public.is_verified_user())
  )
  with check (
    owner_id = (select auth.uid())
    and (select public.is_verified_user())
  );

drop policy if exists "Verified users read their own plant photos"
  on storage.objects;
create policy "Verified users read their own plant photos"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select public.is_verified_user())
  );

drop policy if exists "Verified users upload their own plant photos"
  on storage.objects;
create policy "Verified users upload their own plant photos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select public.is_verified_user())
  );

drop policy if exists "Verified users update their own plant photos"
  on storage.objects;
create policy "Verified users update their own plant photos"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select public.is_verified_user())
  )
  with check (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select public.is_verified_user())
  );

drop policy if exists "Verified users delete their own plant photos"
  on storage.objects;
create policy "Verified users delete their own plant photos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'plant-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select public.is_verified_user())
  );
