create table public.payment_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z0-9_]{2,40}$'),
  name text not null check (length(name) between 2 and 80),
  description text not null default '',
  amount_centavos integer not null check (amount_centavos > 0),
  currency text not null default 'PHP' check (currency = 'PHP'),
  duration_days integer not null check (duration_days between 1 and 3650),
  enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.payment_plans
  (code, name, description, amount_centavos, currency, duration_days, enabled)
values
  ('premium_30_days', 'Premium 30 Days', 'Sample price; configure before enabling.', 4900, 'PHP', 30, false),
  ('premium_365_days', 'Premium 365 Days', 'Sample price; configure before enabling.', 59900, 'PHP', 365, false)
on conflict (code) do nothing;

create table public.premium_payment_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_id uuid not null references public.payment_plans (id),
  payment_method text not null default 'manual_gcash'
    check (payment_method in ('manual_gcash', 'manual_maya', 'manual_maribank')),
  amount_centavos integer not null check (amount_centavos > 0),
  currency text not null check (currency = 'PHP'),
  unique_payment_reference text not null unique,
  merchant_transaction_reference text,
  payment_date date,
  proof_storage_path text,
  payment_status text not null default 'pending'
    check (payment_status in ('pending', 'under_review', 'approved', 'rejected', 'cancelled', 'expired')),
  review_notes text,
  reviewed_by uuid,
  reviewed_at timestamptz,
  entitlement_expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (payment_status in ('pending', 'under_review', 'cancelled', 'expired')
      and reviewed_by is null and reviewed_at is null)
    or (payment_status in ('approved', 'rejected')
      and reviewed_by is not null and reviewed_at is not null)
  )
);

create unique index premium_payment_transaction_reference_unique
  on public.premium_payment_requests (lower(merchant_transaction_reference))
  where merchant_transaction_reference is not null;
create index premium_payment_requests_user_created_idx
  on public.premium_payment_requests (user_id, created_at desc);
create index premium_payment_requests_status_created_idx
  on public.premium_payment_requests (payment_status, created_at desc);

create table public.premium_payment_events (
  id uuid primary key default gen_random_uuid(),
  payment_request_id uuid not null
    references public.premium_payment_requests (id) on delete cascade,
  actor_id uuid,
  previous_status text,
  new_status text not null,
  event_type text not null,
  metadata jsonb not null default '{}'::jsonb
    check (pg_catalog.octet_length(metadata::text) <= 4096),
  created_at timestamptz not null default now()
);
create index premium_payment_events_request_created_idx
  on public.premium_payment_events (payment_request_id, created_at);

create table public.payment_gateway_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  event_id text not null,
  event_type text not null,
  payment_request_id uuid
    references public.premium_payment_requests (id) on delete set null,
  processing_status text not null default 'received'
    check (processing_status in ('received', 'processed', 'ignored', 'failed')),
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
    check (pg_catalog.octet_length(metadata::text) <= 4096),
  unique (provider, event_id)
);

create table public.payment_admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null
);

alter table public.payment_plans enable row level security;
alter table public.premium_payment_requests enable row level security;
alter table public.premium_payment_events enable row level security;
alter table public.payment_gateway_events enable row level security;
alter table public.payment_admins enable row level security;

create policy "Verified users can read enabled payment plans"
  on public.payment_plans for select to authenticated
  using (
    enabled
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );
create policy "Verified users can read their payment requests"
  on public.premium_payment_requests for select to authenticated
  using (
    user_id = (select auth.uid())
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );

revoke all on public.payment_plans, public.premium_payment_requests,
  public.premium_payment_events, public.payment_gateway_events,
  public.payment_admins from public, anon, authenticated;
grant select on public.payment_plans, public.premium_payment_requests
  to authenticated;
grant all on public.payment_plans, public.premium_payment_requests,
  public.premium_payment_events, public.payment_gateway_events,
  public.payment_admins to service_role;
revoke all on public.premium_payment_events from service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'premium-payment-proofs',
  'premium-payment-proofs',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

create policy "Verified users upload their own payment proof"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'premium-payment-proofs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );
create policy "Verified users read their own payment proof"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'premium-payment-proofs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );
create policy "Verified users remove their own payment proof"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'premium-payment-proofs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select auth.jwt() ->> 'email_confirmed_at') is not null
  );

create function public.create_premium_payment_request(
  p_user_id uuid,
  p_plan_code text,
  p_payment_reference text
)
returns public.premium_payment_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_plan public.payment_plans%rowtype;
  created_request public.premium_payment_requests%rowtype;
begin
  if p_user_id is null or p_plan_code is null
    or p_payment_reference is null
    or length(p_payment_reference) not between 8 and 80
  then
    raise exception 'Invalid payment request.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text, 0)
  );

  if exists (
    select 1 from public.premium_payment_requests
    where user_id = p_user_id
      and payment_status in ('pending', 'under_review')
  ) then
    raise exception 'Payment request already open.';
  end if;

  select * into selected_plan
  from public.payment_plans
  where code = p_plan_code and enabled
  for share;

  if not found then
    raise exception 'Payment plan unavailable.';
  end if;

  insert into public.premium_payment_requests (
    user_id, plan_id, amount_centavos, currency, unique_payment_reference
  )
  values (
    p_user_id,
    selected_plan.id,
    selected_plan.amount_centavos,
    selected_plan.currency,
    p_payment_reference
  )
  returning * into created_request;

  insert into public.premium_payment_events (
    payment_request_id, actor_id, previous_status, new_status, event_type
  )
  values (
    created_request.id, p_user_id, null, 'pending', 'request_created'
  );

  return created_request;
end;
$$;

create function public.submit_premium_payment(
  p_user_id uuid,
  p_payment_request_id uuid,
  p_transaction_reference text,
  p_payment_date date,
  p_proof_storage_path text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_request public.premium_payment_requests%rowtype;
begin
  select * into current_request
  from public.premium_payment_requests
  where id = p_payment_request_id and user_id = p_user_id
  for update;

  if not found or current_request.payment_status <> 'pending'
    or p_transaction_reference is null
    or length(btrim(p_transaction_reference)) not between 6 and 80
    or p_payment_date is null
    or p_payment_date > current_date
    or p_payment_date < current_date - 90
    or (p_proof_storage_path is not null
      and p_proof_storage_path not like p_user_id::text || '/' || p_payment_request_id::text || '/%')
  then
    return false;
  end if;

  update public.premium_payment_requests
  set merchant_transaction_reference = btrim(p_transaction_reference),
      payment_date = p_payment_date,
      proof_storage_path = p_proof_storage_path,
      payment_status = 'under_review',
      updated_at = now()
  where id = current_request.id;

  insert into public.premium_payment_events (
    payment_request_id, actor_id, previous_status, new_status, event_type
  )
  values (
    current_request.id, p_user_id, 'pending', 'under_review', 'proof_submitted'
  );

  return true;
exception
  when unique_violation then
    return false;
end;
$$;

create function public.review_premium_payment(
  p_payment_request_id uuid,
  p_reviewer_id uuid,
  p_decision text,
  p_review_notes text
)
returns public.premium_payment_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_request public.premium_payment_requests%rowtype;
  selected_plan public.payment_plans%rowtype;
  updated_request public.premium_payment_requests%rowtype;
  entitlement_start timestamptz;
  entitlement_expiry timestamptz;
begin
  if p_reviewer_id is null or p_decision is null
    or p_decision not in ('approve', 'reject')
    or (p_decision = 'reject'
      and length(btrim(coalesce(p_review_notes, ''))) = 0)
    or length(coalesce(p_review_notes, '')) > 1000
    or not exists (
      select 1 from public.payment_admins
      where user_id = p_reviewer_id
    )
  then
    raise exception 'Unauthorized or invalid review request.';
  end if;

  select * into current_request
  from public.premium_payment_requests
  where id = p_payment_request_id
  for update;
  if not found or current_request.payment_status <> 'under_review' then
    raise exception 'Payment is not awaiting review.';
  end if;

  if p_decision = 'approve' then
    select * into selected_plan
    from public.payment_plans
    where id = current_request.plan_id;
    if not found then
      raise exception 'Payment plan not found.';
    end if;

    select greatest(
      coalesce(max(expires_at) filter (
        where status = 'active' and expires_at > now()
      ), now()),
      now()
    )
    into entitlement_start
    from public.subscription_entitlements
    where user_id = current_request.user_id;
    entitlement_expiry := entitlement_start
      + make_interval(days => selected_plan.duration_days);

    insert into public.subscription_entitlements (
      user_id, product_id, status, expires_at, verified_at, updated_at
    )
    values (
      current_request.user_id, 'manual_gcash', 'active',
      entitlement_expiry, now(), now()
    )
    on conflict (user_id, product_id) do update
    set status = 'active',
        expires_at = greatest(
          case
            when public.subscription_entitlements.status = 'active'
              and public.subscription_entitlements.expires_at > now()
              then public.subscription_entitlements.expires_at
            else now()
          end,
          now(),
          entitlement_start
        ) + make_interval(days => selected_plan.duration_days),
        verified_at = now(),
        updated_at = now();

    update public.premium_payment_requests
    set payment_status = 'approved',
        review_notes = nullif(btrim(coalesce(p_review_notes, '')), ''),
        reviewed_by = p_reviewer_id,
        reviewed_at = now(),
        entitlement_expires_at = entitlement_expiry,
        updated_at = now()
    where id = current_request.id
    returning * into updated_request;
  else
    update public.premium_payment_requests
    set payment_status = 'rejected',
        review_notes = btrim(p_review_notes),
        reviewed_by = p_reviewer_id,
        reviewed_at = now(),
        updated_at = now()
    where id = current_request.id
    returning * into updated_request;
  end if;

  insert into public.premium_payment_events (
    payment_request_id, actor_id, previous_status, new_status, event_type, metadata
  )
  values (
    current_request.id,
    p_reviewer_id,
    'under_review',
    updated_request.payment_status,
    'admin_review',
    jsonb_build_object(
      'decision', p_decision,
      'entitlement_expires_at', updated_request.entitlement_expires_at
    )
  );

  return updated_request;
end;
$$;

create function public.admin_premium_payment_summary(p_admin_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_admin_id is null or not exists (
    select 1 from public.payment_admins where user_id = p_admin_id
  ) then
    raise exception 'Unauthorized.';
  end if;

  return (
    select jsonb_build_object(
      'total', count(*),
      'pending', count(*) filter (where payment_status = 'pending'),
      'under_review', count(*) filter (where payment_status = 'under_review'),
      'approved', count(*) filter (where payment_status = 'approved'),
      'rejected', count(*) filter (where payment_status = 'rejected'),
      'revenue_centavos', coalesce(
        sum(amount_centavos) filter (where payment_status = 'approved'), 0
      )
    )
    from public.premium_payment_requests
  );
end;
$$;

create table public.premium_entitlement_admin_events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null,
  target_user_id uuid not null references auth.users (id) on delete cascade,
  product_id text not null,
  action text not null check (action in ('extend', 'revoke')),
  previous_status text,
  previous_expires_at timestamptz,
  new_status text not null,
  new_expires_at timestamptz,
  review_notes text not null check (length(review_notes) between 1 and 1000),
  created_at timestamptz not null default now()
);
alter table public.premium_entitlement_admin_events enable row level security;
revoke all on public.premium_entitlement_admin_events from public, anon, authenticated;
grant all on public.premium_entitlement_admin_events to service_role;
revoke all on public.premium_entitlement_admin_events from service_role;

create function public.admin_manage_premium_entitlement(
  p_admin_id uuid,
  p_user_id uuid,
  p_product_id text,
  p_action text,
  p_duration_days integer,
  p_review_notes text
)
returns public.subscription_entitlements
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_entitlement public.subscription_entitlements%rowtype;
  updated_entitlement public.subscription_entitlements%rowtype;
begin
  if p_admin_id is null or p_user_id is null
    or p_product_id is null or length(p_product_id) > 80
    or p_action is null
    or p_action not in ('extend', 'revoke')
    or (p_action = 'extend' and (
      p_duration_days is null or p_duration_days < 1 or p_duration_days > 3650
    ))
    or (p_action = 'revoke' and p_duration_days is not null)
    or p_review_notes is null or length(btrim(p_review_notes)) not between 1 and 1000
    or not exists (
      select 1 from public.payment_admins where user_id = p_admin_id
    )
  then
    raise exception 'Unauthorized or invalid entitlement operation.';
  end if;

  select * into existing_entitlement
  from public.subscription_entitlements
  where user_id = p_user_id and product_id = p_product_id
  for update;
  if not found then
    raise exception 'Entitlement not found.';
  end if;

  if p_action = 'extend' then
    update public.subscription_entitlements
    set status = 'active',
        expires_at = greatest(
          case
            when status = 'active' and expires_at > now() then expires_at
            else now()
          end,
          now()
        )
          + make_interval(days => p_duration_days),
        verified_at = now(),
        updated_at = now()
    where user_id = p_user_id and product_id = p_product_id
    returning * into updated_entitlement;
  else
    update public.subscription_entitlements
    set status = 'revoked', updated_at = now()
    where user_id = p_user_id and product_id = p_product_id
    returning * into updated_entitlement;
  end if;

  insert into public.premium_entitlement_admin_events (
    actor_id, target_user_id, product_id, action,
    previous_status, previous_expires_at, new_status, new_expires_at,
    review_notes
  )
  values (
    p_admin_id,
    p_user_id,
    p_product_id,
    p_action,
    existing_entitlement.status,
    existing_entitlement.expires_at,
    updated_entitlement.status,
    updated_entitlement.expires_at,
    btrim(p_review_notes)
  );
  return updated_entitlement;
end;
$$;

revoke all on function public.create_premium_payment_request(uuid, text, text)
  from public, anon, authenticated;
revoke all on function public.submit_premium_payment(uuid, uuid, text, date, text)
  from public, anon, authenticated;
revoke all on function public.review_premium_payment(uuid, uuid, text, text)
  from public, anon, authenticated;
revoke all on function public.admin_premium_payment_summary(uuid)
  from public, anon, authenticated;
revoke all on function public.admin_manage_premium_entitlement(uuid, uuid, text, text, integer, text)
  from public, anon, authenticated;
grant execute on function public.create_premium_payment_request(uuid, text, text)
  to service_role;
grant execute on function public.submit_premium_payment(uuid, uuid, text, date, text)
  to service_role;
grant execute on function public.review_premium_payment(uuid, uuid, text, text)
  to service_role;
grant execute on function public.admin_premium_payment_summary(uuid)
  to service_role;
grant execute on function public.admin_manage_premium_entitlement(uuid, uuid, text, text, integer, text)
  to service_role;
