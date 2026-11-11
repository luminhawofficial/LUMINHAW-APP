create table public.admin_roles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role text not null check (role in ('super_admin', 'admin', 'moderator')),
  status text not null default 'active'
    check (status in ('active', 'suspended')),
  assigned_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index admin_roles_status_role_idx
  on public.admin_roles (status, role);

create table public.admin_activity_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users (id) on delete set null,
  action text not null check (action ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  resource_type text not null
    check (resource_type ~ '^[a-z][a-z0-9_.-]{0,39}$'),
  resource_id text check (resource_id is null or length(resource_id) <= 120),
  metadata jsonb not null default '{}'::jsonb
    check (
      jsonb_typeof(metadata) = 'object'
      and octet_length(metadata::text) <= 4096
    ),
  created_at timestamptz not null default now()
);

create index admin_activity_logs_actor_created_idx
  on public.admin_activity_logs (actor_id, created_at desc);
create index admin_activity_logs_resource_created_idx
  on public.admin_activity_logs (resource_type, resource_id, created_at desc);

alter table public.admin_roles enable row level security;
alter table public.admin_activity_logs enable row level security;

revoke all on public.admin_roles, public.admin_activity_logs
  from public, anon, authenticated;
grant all on public.admin_roles, public.admin_activity_logs to service_role;

create function public.admin_set_role(
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
  active_super_admins integer;
begin
  if p_actor_id is null or p_target_user_id is null
    or p_role is null or p_status is null
    or p_role not in ('super_admin', 'admin', 'moderator')
    or p_status not in ('active', 'suspended')
    or not exists (
      select 1
      from public.admin_roles
      where user_id = p_actor_id
        and role = 'super_admin'
        and status = 'active'
    )
    or not exists (
      select 1 from auth.users where id = p_target_user_id
    )
  then
    raise exception 'Unauthorized or invalid administrator assignment.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('luminhaw-admin-super-admin-roster', 0)
  );

  select * into current_target
  from public.admin_roles
  where user_id = p_target_user_id
  for update;

  if current_target.role = 'super_admin'
    and current_target.status = 'active'
    and (p_role <> 'super_admin' or p_status <> 'active')
  then
    select count(*) into active_super_admins
    from public.admin_roles
    where role = 'super_admin' and status = 'active';

    if active_super_admins <= 1 then
      raise exception 'The final active Super Admin cannot be demoted or suspended.';
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

create function public.admin_write_audit_log(
  p_actor_id uuid,
  p_action text,
  p_resource_type text,
  p_resource_id text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  log_id uuid;
begin
  if p_actor_id is null
    or p_action is null
    or p_action !~ '^[a-z][a-z0-9_.-]{1,79}$'
    or p_resource_type is null
    or p_resource_type !~ '^[a-z][a-z0-9_.-]{0,39}$'
    or (p_resource_id is not null and length(p_resource_id) > 120)
    or p_metadata is null
    or jsonb_typeof(p_metadata) <> 'object'
    or octet_length(p_metadata::text) > 4096
    or not exists (
      select 1
      from public.admin_roles
      where user_id = p_actor_id and status = 'active'
    )
  then
    raise exception 'Unauthorized or invalid audit event.';
  end if;

  insert into public.admin_activity_logs (
    actor_id, action, resource_type, resource_id, metadata
  )
  values (p_actor_id, p_action, p_resource_type, p_resource_id, p_metadata)
  returning id into log_id;

  return log_id;
end;
$$;

create function public.admin_dashboard_summary(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  summary jsonb;
begin
  if p_actor_id is null or not exists (
    select 1
    from public.admin_roles
    where user_id = p_actor_id and status = 'active'
  ) then
    raise exception 'Unauthorized.';
  end if;

  select jsonb_build_object(
    'metrics', jsonb_build_object(
      'total_users', (select count(*) from auth.users),
      'active_users_30d', (
        select count(*) from auth.users
        where last_sign_in_at >= pg_catalog.now() - interval '30 days'
      ),
      'verified_users', (
        select count(*) from auth.users where email_confirmed_at is not null
      ),
      'plant_scans', (select count(*) from public.plant_identifications),
      'identified_plants', (
        select count(distinct coalesce(
          result #>> '{classification,suggestions,0,details,scientific_name}',
          result #>> '{classification,suggestions,0,name}'
        ))
        from public.plant_identifications
        where status = 'completed' and result is not null
      ),
      'garden_plants', (select count(*) from public.plants),
      'premium_subscribers', (
        select count(distinct user_id)
        from public.subscription_entitlements
        where status = 'active' and expires_at > pg_catalog.now()
      ),
      'pending_payments', (
        select count(*) from public.premium_payment_requests
        where payment_status in ('pending', 'under_review')
      ),
      'approved_payments', (
        select count(*) from public.premium_payment_requests
        where payment_status = 'approved'
      ),
      'subscription_revenue_php', (
        select coalesce(sum(amount_centavos), 0)::numeric / 100
        from public.premium_payment_requests
        where payment_status = 'approved'
      )
    ),
    'monthly', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'month', pg_catalog.to_char(months.month_start, 'YYYY-MM'),
            'new_users', months.new_users,
            'plant_scans', months.plant_scans,
            'revenue_php', months.revenue_php
          )
          order by months.month_start
        ),
        '[]'::jsonb
      )
      from (
        select
          series.month_start,
          (
            select count(*) from auth.users
            where created_at >= series.month_start
              and created_at < series.month_start + interval '1 month'
          ) as new_users,
          (
            select count(*) from public.plant_identifications
            where created_at >= series.month_start
              and created_at < series.month_start + interval '1 month'
          ) as plant_scans,
          (
            select coalesce(sum(amount_centavos), 0)::numeric / 100
            from public.premium_payment_requests
            where payment_status = 'approved'
              and reviewed_at >= series.month_start
              and reviewed_at < series.month_start + interval '1 month'
          ) as revenue_php
        from pg_catalog.generate_series(
          pg_catalog.date_trunc('month', pg_catalog.now()) - interval '5 months',
          pg_catalog.date_trunc('month', pg_catalog.now()),
          interval '1 month'
        ) as series(month_start)
      ) as months
    ),
    'monthly_active_users', jsonb_build_object(
      'available', false,
      'reason', 'Historical monthly activity is not stored in the existing schema.'
    ),
    'top_plants', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'scientific_name', popular.scientific_name,
            'identifications', popular.identifications
          )
          order by popular.identifications desc, popular.scientific_name
        ),
        '[]'::jsonb
      )
      from (
        select
          coalesce(
            result #>> '{classification,suggestions,0,details,scientific_name}',
            result #>> '{classification,suggestions,0,name}'
          ) as scientific_name,
          count(*) as identifications
        from public.plant_identifications
        where status = 'completed' and result is not null
        group by 1
        having coalesce(
          result #>> '{classification,suggestions,0,details,scientific_name}',
          result #>> '{classification,suggestions,0,name}'
        ) is not null
        order by count(*) desc
        limit 5
      ) as popular
    )
  ) into summary;

  return summary;
end;
$$;

create function public.admin_list_users(
  p_actor_id uuid,
  p_search text default null,
  p_limit integer default 25,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if p_actor_id is null
    or p_limit is null or p_limit not between 1 and 100
    or p_offset is null or p_offset not between 0 and 1000000
    or (p_search is not null and length(p_search) > 120)
    or not exists (
      select 1
      from public.admin_roles
      where user_id = p_actor_id and status = 'active'
    )
  then
    raise exception 'Unauthorized or invalid user query.';
  end if;

  with matching_users as materialized (
    select
      users.id,
      users.email,
      users.created_at,
      users.email_confirmed_at,
      users.last_sign_in_at,
      users.banned_until,
      coalesce(profiles.display_name, '') as display_name,
      admin_roles.role as admin_role,
      admin_roles.status as admin_status,
      entitlement.product_id as entitlement_product_id,
      entitlement.expires_at as entitlement_expires_at
    from auth.users as users
    left join public.profiles as profiles on profiles.id = users.id
    left join public.admin_roles as admin_roles on admin_roles.user_id = users.id
    left join lateral (
      select entitlements.product_id, entitlements.expires_at
      from public.subscription_entitlements as entitlements
      where entitlements.user_id = users.id
        and entitlements.status = 'active'
        and entitlements.expires_at > pg_catalog.now()
      order by entitlements.expires_at desc
      limit 1
    ) as entitlement on true
    where p_search is null
      or p_search = ''
      or pg_catalog.strpos(
        pg_catalog.lower(coalesce(users.email, '')),
        pg_catalog.lower(p_search)
      ) > 0
      or pg_catalog.strpos(
        pg_catalog.lower(coalesce(profiles.display_name, '')),
        pg_catalog.lower(p_search)
      ) > 0
      or users.id::text = p_search
  ),
  page as (
    select *
    from matching_users
    order by created_at desc, id
    limit p_limit offset p_offset
  )
  select jsonb_build_object(
    'total', (select count(*) from matching_users),
    'users', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', id,
            'email', email,
            'display_name', display_name,
            'created_at', created_at,
            'email_verified', email_confirmed_at is not null,
            'last_sign_in_at', last_sign_in_at,
            'account_status', case
              when banned_until > pg_catalog.now() then 'suspended'
              else 'active'
            end,
            'admin_role', admin_role,
            'admin_status', admin_status,
            'subscription_product_id', entitlement_product_id,
            'subscription_expires_at', entitlement_expires_at
          )
          order by created_at desc, id
        )
        from page
      ),
      '[]'::jsonb
    )
  ) into result;

  return result;
end;
$$;

create function public.admin_review_premium_payment(
  p_actor_id uuid,
  p_payment_request_id uuid,
  p_decision text,
  p_confirm_received boolean,
  p_review_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_request public.premium_payment_requests%rowtype;
  selected_plan public.payment_plans%rowtype;
  updated_request public.premium_payment_requests%rowtype;
  actor_email text;
  entitlement_expiry timestamptz;
begin
  if p_actor_id is null
    or p_payment_request_id is null
    or p_decision is null
    or p_decision not in ('approve', 'reject')
    or (p_decision = 'approve' and p_confirm_received is not true)
    or (p_decision = 'reject'
      and length(pg_catalog.btrim(coalesce(p_review_notes, '')))
        not between 1 and 1000)
    or length(coalesce(p_review_notes, '')) > 1000
    or not exists (
      select 1
      from public.admin_roles
      where user_id = p_actor_id
        and role = 'super_admin'
        and status = 'active'
    )
  then
    raise exception 'Unauthorized or invalid payment review.';
  end if;

  select lower(email) into actor_email
  from auth.users
  where id = p_actor_id;

  if actor_email is null then
    raise exception 'Administrator account not found.';
  end if;

  select * into current_request
  from public.premium_payment_requests
  where id = p_payment_request_id
  for update;

  if not found or current_request.payment_status <> 'under_review' then
    raise exception 'Payment is not awaiting review.';
  end if;

  if p_decision = 'approve'
    and lower(coalesce(current_request.customer_email, '')) = actor_email
  then
    raise exception 'An administrator cannot approve their own payment.';
  end if;

  if p_decision = 'approve' then
    select * into selected_plan
    from public.payment_plans
    where id = current_request.plan_id;

    if not found then
      raise exception 'Payment plan not found.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(current_request.user_id::text, 0)
    );

    select greatest(
      coalesce(pg_catalog.max(expires_at) filter (
        where status = 'active' and expires_at > pg_catalog.now()
      ), pg_catalog.now()),
      pg_catalog.now()
    )
    into entitlement_expiry
    from public.subscription_entitlements
    where user_id = current_request.user_id;

    entitlement_expiry := entitlement_expiry
      + pg_catalog.make_interval(days => selected_plan.duration_days);

    insert into public.subscription_entitlements (
      user_id, product_id, status, expires_at, verified_at, updated_at
    )
    values (
      current_request.user_id,
      'manual_gcash',
      'active',
      entitlement_expiry,
      pg_catalog.now(),
      pg_catalog.now()
    )
    on conflict (user_id, product_id) do update
    set status = 'active',
        expires_at = excluded.expires_at,
        verified_at = excluded.verified_at,
        updated_at = excluded.updated_at;

    update public.premium_payment_requests
    set payment_status = 'approved',
        reviewed_by = p_actor_id,
        reviewed_by_email = null,
        reviewed_at = pg_catalog.now(),
        transaction_received_confirmed = true,
        entitlement_expires_at = entitlement_expiry,
        review_notes = nullif(pg_catalog.btrim(coalesce(p_review_notes, '')), ''),
        rejection_reason = null,
        updated_at = pg_catalog.now()
    where id = current_request.id
    returning * into updated_request;
  else
    update public.premium_payment_requests
    set payment_status = 'rejected',
        reviewed_by = p_actor_id,
        reviewed_by_email = null,
        reviewed_at = pg_catalog.now(),
        transaction_received_confirmed = false,
        review_notes = pg_catalog.btrim(p_review_notes),
        rejection_reason = pg_catalog.btrim(p_review_notes),
        updated_at = pg_catalog.now()
    where id = current_request.id
    returning * into updated_request;
  end if;

  insert into public.premium_payment_events (
    payment_request_id, actor_id, previous_status, new_status, event_type,
    metadata
  )
  values (
    current_request.id,
    p_actor_id,
    'under_review',
    updated_request.payment_status,
    'admin_review',
    jsonb_build_object(
      'decision', p_decision,
      'transaction_received_confirmed', p_decision = 'approve',
      'entitlement_expires_at', updated_request.entitlement_expires_at
    )
  );

  insert into public.admin_activity_logs (
    actor_id, action, resource_type, resource_id, metadata
  )
  values (
    p_actor_id,
    'payment.reviewed',
    'payment',
    current_request.id::text,
    jsonb_build_object(
      'decision', p_decision,
      'payment_status', updated_request.payment_status
    )
  );

  return jsonb_build_object(
    'payment_request_id', updated_request.id,
    'decision', p_decision,
    'payment_status', updated_request.payment_status,
    'entitlement_expires_at', updated_request.entitlement_expires_at
  );
end;
$$;

revoke all on function public.admin_set_role(uuid, uuid, text, text)
  from public, anon, authenticated;
revoke all on function public.admin_write_audit_log(uuid, text, text, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.admin_dashboard_summary(uuid)
  from public, anon, authenticated;
revoke all on function public.admin_list_users(uuid, text, integer, integer)
  from public, anon, authenticated;
revoke all on function public.admin_review_premium_payment(uuid, uuid, text, boolean, text)
  from public, anon, authenticated;

grant execute on function public.admin_set_role(uuid, uuid, text, text)
  to service_role;
grant execute on function public.admin_write_audit_log(uuid, text, text, text, jsonb)
  to service_role;
grant execute on function public.admin_dashboard_summary(uuid)
  to service_role;
grant execute on function public.admin_list_users(uuid, text, integer, integer)
  to service_role;
grant execute on function public.admin_review_premium_payment(uuid, uuid, text, boolean, text)
  to service_role;