drop policy if exists "Premium users manage their own growth entries"
  on public.growth_entries;
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

drop policy if exists "Premium users manage their own care activities"
  on public.care_activities;
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
