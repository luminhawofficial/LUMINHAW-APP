alter table public.subscription_entitlements
  add column if not exists plan_code text,
  add column if not exists starts_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'subscription_entitlements_plan_code_fkey'
      and conrelid = 'public.subscription_entitlements'::regclass
  ) then
    alter table public.subscription_entitlements
      add constraint subscription_entitlements_plan_code_fkey
      foreign key (plan_code) references public.payment_plans(code);
  end if;
end;
$$;

update public.subscription_entitlements as entitlement
set plan_code = coalesce(
      entitlement.plan_code,
      (
        select plan.code
        from public.premium_payment_requests as request
        join public.payment_plans as plan on plan.id = request.plan_id
        where request.user_id = entitlement.user_id
          and request.payment_status = 'approved'
          and request.entitlement_expires_at = entitlement.expires_at
        order by request.reviewed_at desc
        limit 1
      )
    ),
    starts_at = coalesce(
      entitlement.starts_at,
      (
        select request.entitlement_expires_at
          - pg_catalog.make_interval(days => plan.duration_days)
        from public.premium_payment_requests as request
        join public.payment_plans as plan on plan.id = request.plan_id
        where request.user_id = entitlement.user_id
          and request.payment_status = 'approved'
          and request.entitlement_expires_at = entitlement.expires_at
        order by request.reviewed_at desc
        limit 1
      ),
      entitlement.verified_at
    )
where entitlement.product_id = 'manual_gcash'
  and (entitlement.plan_code is null or entitlement.starts_at is null);

create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  notification_type text not null,
  title text not null check (length(title) between 1 and 200),
  message text not null check (length(message) between 1 and 2000),
  payment_request_id uuid not null
    references public.premium_payment_requests (id) on delete cascade,
  created_at timestamptz not null default pg_catalog.now(),
  unique (payment_request_id, notification_type)
);

create index if not exists user_notifications_user_created_idx
  on public.user_notifications (user_id, created_at desc);

alter table public.user_notifications enable row level security;
drop policy if exists "Users read their own notifications"
  on public.user_notifications;
create policy "Users read their own notifications"
  on public.user_notifications for select to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.user_notifications from public, anon, authenticated;
grant select on public.user_notifications to authenticated;
grant all on public.user_notifications to service_role;

do $$
begin
  if exists (
    select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime'
  ) then
    if not exists (
      select 1 from pg_catalog.pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'subscription_entitlements'
    ) then
      alter publication supabase_realtime
        add table public.subscription_entitlements;
    end if;
    if not exists (
      select 1 from pg_catalog.pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'user_notifications'
    ) then
      alter publication supabase_realtime
        add table public.user_notifications;
    end if;
  end if;
end;
$$;

create or replace function public.record_premium_approval_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_plan public.payment_plans%rowtype;
  entitlement_start timestamptz;
begin
  if old.payment_status is distinct from new.payment_status
    and new.payment_status = 'approved'
  then
    if new.reviewed_at is null
      or (new.reviewed_by is null and new.reviewed_by_email is null)
      or new.transaction_received_confirmed is not true
      or new.entitlement_expires_at is null
    then
      raise exception 'Approved payment is missing verified review details.';
    end if;

    select * into selected_plan
    from public.payment_plans
    where id = new.plan_id
    for share;

    if not found then
      raise exception 'Payment plan not found.';
    end if;

    entitlement_start := new.entitlement_expires_at
      - pg_catalog.make_interval(days => selected_plan.duration_days);

    update public.subscription_entitlements
    set plan_code = selected_plan.code,
        starts_at = entitlement_start,
        verified_at = entitlement_start,
        updated_at = new.reviewed_at
    where user_id = new.user_id
      and product_id = 'manual_gcash'
      and status = 'active'
      and expires_at = new.entitlement_expires_at;

    if not found then
      raise exception 'Premium entitlement was not activated for approved payment.';
    end if;

    insert into public.user_notifications (
      user_id, notification_type, title, message, payment_request_id
    )
    values (
      new.user_id,
      'premium_activated',
      'Congratulations! You''re now a LUMINHAW Premium Member! 🎉',
      'Your payment has been successfully verified and approved. Your LUMINHAW Premium subscription is now active!'
        || E'\n\n'
        || 'Enjoy your exclusive Premium features, advanced plant identification, plant health insights, and more. Thank you for choosing LUMINHAW!',
      new.id
    )
    on conflict (payment_request_id, notification_type) do nothing;
  end if;

  return new;
end;
$$;

revoke all on function public.record_premium_approval_notification()
  from public, anon, authenticated;
grant execute on function public.record_premium_approval_notification()
  to service_role;

drop trigger if exists premium_approval_notification
  on public.premium_payment_requests;
create trigger premium_approval_notification
after update of payment_status on public.premium_payment_requests
for each row
execute function public.record_premium_approval_notification();
