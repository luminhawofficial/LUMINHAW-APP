-- Focused repair for the existing announcements feed only.
-- Run in the Supabase SQL Editor after review. This does not mark any
-- Supabase migration versions as applied.

begin;

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

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.system_announcements'::regclass
      and conname = 'system_announcements_audience_check'
  ) then
    alter table public.system_announcements
      add constraint system_announcements_audience_check
      check (audience in ('all', 'free', 'premium'));
  end if;
end;
$$;

create index if not exists system_announcements_audience_published_idx
  on public.system_announcements (audience, published_at desc)
  where is_active;

drop policy if exists "Anyone can read published system announcements"
  on public.system_announcements;
drop policy if exists "Users can read published announcements for their audience"
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

commit;
