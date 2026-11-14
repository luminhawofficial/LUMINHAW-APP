alter table public.profiles
  add column if not exists username text,
  add column if not exists gender text,
  add column if not exists date_of_birth date,
  add column if not exists phone_number text,
  add column if not exists location text,
  add column if not exists bio text,
  add column if not exists gardening_experience text,
  add column if not exists favorite_plant_category text,
  add column if not exists growing_environment text,
  add column if not exists avatar_hidden boolean not null default false;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_username_format_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_username_format_check
      check (
        username is null
        or username ~ '^[a-z0-9][a-z0-9._]{2,29}$'
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_gender_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_gender_check
      check (gender is null or gender in ('Male', 'Female', 'Prefer not to say'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_bio_length_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_bio_length_check
      check (bio is null or char_length(bio) <= 150);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_gardening_experience_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_gardening_experience_check
      check (
        gardening_experience is null
        or gardening_experience in ('Beginner', 'Intermediate', 'Expert')
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_favorite_plant_category_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_favorite_plant_category_check
      check (
        favorite_plant_category is null
        or favorite_plant_category in (
          'Flowers',
          'Vegetables',
          'Fruits',
          'Herbs',
          'Indoor Plants',
          'Trees',
          'Succulents',
          'Others'
        )
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_growing_environment_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_growing_environment_check
      check (
        growing_environment is null
        or growing_environment in ('Indoor', 'Outdoor', 'Both')
      );
  end if;
end
$$;

create unique index if not exists profiles_username_ci_unique
  on public.profiles (lower(username))
  where username is not null;

create or replace function public.is_profile_username_available(
  p_username text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and coalesce(p_username ~ '^[a-z0-9][a-z0-9._]{2,29}$', false)
    and not exists (
      select 1
      from public.profiles
      where username is not null
        and lower(username) = lower(btrim(p_username))
        and id <> (select auth.uid())
    );
$$;

revoke all on function public.is_profile_username_available(text) from public;
grant execute on function public.is_profile_username_available(text)
  to authenticated;
