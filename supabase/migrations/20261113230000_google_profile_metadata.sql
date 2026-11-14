create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_name text;
begin
  profile_name := coalesce(
    nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'name'), ''),
    nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'display_name'), ''),
    ''
  );

  insert into public.profiles (id, display_name)
  values (new.id, profile_name)
  on conflict (id) do update
  set display_name = case
        when pg_catalog.btrim(public.profiles.display_name) = ''
          then excluded.display_name
        else public.profiles.display_name
      end,
      updated_at = pg_catalog.now();

  return new;
end;
$$;

update public.profiles as profile
set display_name = coalesce(
      nullif(pg_catalog.btrim(user_row.raw_user_meta_data ->> 'full_name'), ''),
      nullif(pg_catalog.btrim(user_row.raw_user_meta_data ->> 'name'), ''),
      nullif(pg_catalog.btrim(user_row.raw_user_meta_data ->> 'display_name'), ''),
      ''
    ),
    updated_at = pg_catalog.now()
from auth.users as user_row
where profile.id = user_row.id
  and pg_catalog.btrim(profile.display_name) = ''
  and coalesce(
    nullif(pg_catalog.btrim(user_row.raw_user_meta_data ->> 'full_name'), ''),
    nullif(pg_catalog.btrim(user_row.raw_user_meta_data ->> 'name'), ''),
    nullif(pg_catalog.btrim(user_row.raw_user_meta_data ->> 'display_name'), '')
  ) is not null;
