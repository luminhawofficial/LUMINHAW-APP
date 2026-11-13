do $$
declare
  active_admin_candidates integer;
begin
  select count(*) into active_admin_candidates
  from public.admin_roles
  where status = 'active'
    and role in ('admin', 'super_admin');

  if active_admin_candidates > 1 then
    raise exception
      'Role migration allows at most one active Admin candidate; found %.',
      active_admin_candidates;
  end if;
end;
$$;

update public.admin_roles
set role = case when status = 'active' then 'admin' else 'moderator' end,
    updated_at = pg_catalog.clock_timestamp()
where role = 'super_admin';

alter table public.admin_roles
  drop constraint admin_roles_role_check,
  add constraint admin_roles_role_check
    check (role in ('admin', 'moderator'));

create unique index if not exists admin_roles_one_active_admin_idx
  on public.admin_roles (role)
  where role = 'admin' and status = 'active';

create or replace function public.admin_set_role(
  p_actor_id uuid,
  p_target_user_id uuid,
  p_role text,
  p_status text
)
returns public.admin_roles
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_target public.admin_roles%rowtype;
  updated_target public.admin_roles%rowtype;
  active_admins integer;
begin
  if p_actor_id is null or p_target_user_id is null
    or p_role is null or p_status is null
    or p_role not in ('admin', 'moderator')
    or p_status not in ('active', 'suspended')
    or not exists (
      select 1
      from public.admin_roles
      where user_id = p_actor_id
        and role = 'admin'
        and status = 'active'
    )
    or not exists (
      select 1 from auth.users where id = p_target_user_id
    )
  then
    raise exception 'Unauthorized or invalid administrator assignment.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('luminhaw-admin-role-roster', 0)
  );

  select * into current_target
  from public.admin_roles
  where user_id = p_target_user_id
  for update;

  if p_role = 'admin' and p_status = 'active'
    and (current_target.role is distinct from 'admin'
      or current_target.status is distinct from 'active')
    and exists (
      select 1
      from public.admin_roles
      where role = 'admin' and status = 'active'
    )
  then
    raise exception 'Only one active Admin account is allowed.';
  end if;

  if current_target.role = 'admin'
    and current_target.status = 'active'
    and (p_role <> 'admin' or p_status <> 'active')
  then
    select count(*) into active_admins
    from public.admin_roles
    where role = 'admin' and status = 'active';

    if active_admins <= 1 then
      raise exception 'The final active Admin cannot be demoted or suspended.';
    end if;
  end if;

  insert into public.admin_roles (user_id, role, status, assigned_by)
  values (p_target_user_id, p_role, p_status, p_actor_id)
  on conflict (user_id) do update
  set role = excluded.role,
      status = excluded.status,
      assigned_by = excluded.assigned_by,
      updated_at = pg_catalog.clock_timestamp()
  returning * into updated_target;

  insert into public.admin_activity_logs (
    actor_id, action, resource_type, resource_id, metadata
  )
  values (
    p_actor_id,
    'admin.role_changed',
    'admin',
    p_target_user_id::text,
    jsonb_build_object(
      'previous_role', current_target.role,
      'previous_status', current_target.status,
      'role', updated_target.role,
      'status', updated_target.status
    )
  );

  return updated_target;
end;
$$;

revoke all on function public.admin_set_role(uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.admin_set_role(uuid, uuid, text, text)
  to service_role;
