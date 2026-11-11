alter table public.plant_catalog
  add column if not exists tagalog_name text,
  add column if not exists bisaya_name text,
  add column if not exists origin text,
  add column if not exists compatible_weather text,
  add column if not exists is_verified boolean not null default false,
  add column if not exists is_active boolean not null default true,
  add column if not exists verification_status text not null default 'pending',
  add column if not exists verified_at timestamptz;

alter table public.plant_catalog
  add constraint plant_catalog_verification_status_check
  check (verification_status in ('pending', 'verified', 'rejected'));

create index if not exists plant_catalog_verified_names_idx
  on public.plant_catalog (lower(scientific_name), lower(common_name))
  where is_verified and is_active;

alter table public.plant_care
  add column if not exists water_requirements text,
  add column if not exists sunlight_requirements text,
  add column if not exists soil_requirements text,
  add column if not exists compatible_weather text;

alter table public.plant_images
  add column if not exists license_url text,
  add column if not exists is_verified boolean not null default false;

drop policy if exists "Verified catalog visible to signed-in users"
  on public.plant_catalog;
create policy "Verified catalog visible to signed-in users"
  on public.plant_catalog for select to authenticated
  using (is_verified and is_active);

drop policy if exists "Reviewed care visible to signed-in users"
  on public.plant_care;
create policy "Reviewed care visible to signed-in users"
  on public.plant_care for select to authenticated
  using (
    reviewed
    and exists (
      select 1
      from public.plant_catalog
      where plant_catalog.id = plant_care.plant_id
        and plant_catalog.is_verified
        and plant_catalog.is_active
    )
  );

drop policy if exists "Verified images visible to signed-in users"
  on public.plant_images;
create policy "Verified images visible to signed-in users"
  on public.plant_images for select to authenticated
  using (
    is_verified
    and exists (
      select 1
      from public.plant_catalog
      where plant_catalog.id = plant_images.plant_id
        and plant_catalog.is_verified
        and plant_catalog.is_active
    )
  );

grant select on public.plant_catalog, public.plant_care, public.plant_images
  to authenticated;

alter table public.system_announcements
  add column if not exists audience text not null default 'all',
  add column if not exists dismissible boolean not null default true;

alter table public.system_announcements
  drop constraint if exists system_announcements_category_check;
alter table public.system_announcements
  add constraint system_announcements_category_check
  check (
    category in (
      'update',
      'maintenance',
      'feature',
      'account',
      'promotion',
      'plant_care'
    )
  );
alter table public.system_announcements
  add constraint system_announcements_audience_check
  check (audience in ('all', 'free', 'premium'));

create index if not exists system_announcements_audience_published_idx
  on public.system_announcements (audience, published_at desc)
  where is_active;

drop policy if exists "Anyone can read published system announcements"
  on public.system_announcements;
create policy "Users can read published announcements for their audience"
  on public.system_announcements for select to anon, authenticated
  using (
    is_active
    and published_at <= now()
    and (expires_at is null or expires_at > now())
    and (
      audience = 'all'
      or (
        auth.uid() is not null
        and audience = 'premium'
        and exists (
          select 1
          from public.subscription_entitlements
          where subscription_entitlements.user_id = auth.uid()
            and subscription_entitlements.status = 'active'
            and subscription_entitlements.expires_at > now()
        )
      )
      or (
        auth.uid() is not null
        and audience = 'free'
        and not exists (
          select 1
          from public.subscription_entitlements
          where subscription_entitlements.user_id = auth.uid()
            and subscription_entitlements.status = 'active'
            and subscription_entitlements.expires_at > now()
        )
      )
    )
  );
