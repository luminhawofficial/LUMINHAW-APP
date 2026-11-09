alter table public.profiles
  add column if not exists avatar_url text;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'avatars',
  'avatars',
  true,
  1000000,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Verified users read their own avatars"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and storage.filename(name) ~ '^avatar_[0-9]+[.](jpg|png|webp)$'
    and (select public.is_verified_user())
  );

create policy "Verified users upload their own avatars"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and storage.filename(name) ~ '^avatar_[0-9]+[.](jpg|png|webp)$'
    and (select public.is_verified_user())
  );

create policy "Verified users update their own avatars"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and storage.filename(name) ~ '^avatar_[0-9]+[.](jpg|png|webp)$'
    and (select public.is_verified_user())
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and storage.filename(name) ~ '^avatar_[0-9]+[.](jpg|png|webp)$'
    and (select public.is_verified_user())
  );

create policy "Verified users delete their own avatars"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and storage.filename(name) ~ '^avatar_[0-9]+[.](jpg|png|webp)$'
    and (select public.is_verified_user())
  );
