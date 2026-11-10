drop policy if exists "Verified users manage their own growth entries"
  on public.growth_entries;
create policy "Premium users manage their own growth entries"
  on public.growth_entries for all to authenticated
  using (
    owner_id = (select auth.uid())
    and (select public.is_verified_user())
    and exists (
      select 1
      from public.subscription_entitlements entitlement
      where entitlement.user_id = (select auth.uid())
        and entitlement.status = 'active'
        and entitlement.expires_at > now()
    )
  )
  with check (
    owner_id = (select auth.uid())
    and (select public.is_verified_user())
    and exists (
      select 1
      from public.subscription_entitlements entitlement
      where entitlement.user_id = (select auth.uid())
        and entitlement.status = 'active'
        and entitlement.expires_at > now()
    )
  );

drop policy if exists "Verified users manage their own care activities"
  on public.care_activities;
create policy "Premium users manage their own care activities"
  on public.care_activities for all to authenticated
  using (
    owner_id = (select auth.uid())
    and (select public.is_verified_user())
    and exists (
      select 1
      from public.subscription_entitlements entitlement
      where entitlement.user_id = (select auth.uid())
        and entitlement.status = 'active'
        and entitlement.expires_at > now()
    )
  )
  with check (
    owner_id = (select auth.uid())
    and (select public.is_verified_user())
    and exists (
      select 1
      from public.subscription_entitlements entitlement
      where entitlement.user_id = (select auth.uid())
        and entitlement.status = 'active'
        and entitlement.expires_at > now()
    )
  );
