alter table public.payment_email_notifications
  add column if not exists delivery_claimed_at timestamptz,
  add column if not exists delivery_claim_token uuid;

alter table public.payment_email_notifications
  drop constraint if exists payment_email_notifications_delivery_status_check;
alter table public.payment_email_notifications
  add constraint payment_email_notifications_delivery_status_check
  check (delivery_status in ('pending', 'sending', 'sent', 'failed', 'suppressed'));

update public.payment_email_notifications as notification
set delivery_status = 'suppressed',
    last_error_code = 'in_app_only',
    delivery_claimed_at = null,
    delivery_claim_token = null,
    updated_at = pg_catalog.now()
from public.premium_payment_requests as payment
where notification.payment_request_id = payment.id
  and notification.notification_type = 'customer_payment_reviewed'
  and payment.payment_status = 'approved'
  and notification.delivery_status in ('pending', 'failed', 'sending');

create or replace function public.queue_customer_payment_review_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.payment_status is distinct from new.payment_status
    and new.payment_status = 'rejected'
    and (new.reviewed_by is not null or new.reviewed_by_email is not null)
    and new.customer_email is not null
  then
    insert into public.payment_email_notifications (
      payment_request_id, notification_type, recipient_email
    )
    values (
      new.id, 'customer_payment_reviewed', new.customer_email
    )
    on conflict (payment_request_id, notification_type) do nothing;
  end if;
  return new;
end;
$$;

create or replace function public.claim_payment_email_notification(
  p_notification_id uuid
)
returns table (
  claimed boolean,
  attempt_count integer,
  claim_token uuid
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  update public.payment_email_notifications as notification
  set delivery_status = 'sending',
      delivery_claimed_at = pg_catalog.now(),
      delivery_claim_token = gen_random_uuid(),
      attempt_count = notification.attempt_count + 1,
      updated_at = pg_catalog.now()
  where notification.id = p_notification_id
    and (
      notification.delivery_status in ('pending', 'failed')
      or (
        notification.delivery_status = 'sending'
        and notification.delivery_claimed_at
          < pg_catalog.now() - interval '15 minutes'
      )
    )
  returning true, notification.attempt_count, notification.delivery_claim_token;
  if not found then
    return query select false, 0, null::uuid;
  end if;
end;
$$;

update public.user_notifications
set message =
  'Your payment has been successfully verified and approved. Your LUMINHAW Premium subscription is now active!'
  || E'\n\n'
  || 'Enjoy your exclusive Premium features, advanced plant identification, plant health insights, and more. Thank you for your support!'
where notification_type = 'premium_activated';

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
        || 'Enjoy your exclusive Premium features, advanced plant identification, plant health insights, and more. Thank you for your support!',
      new.id
    )
    on conflict (payment_request_id, notification_type) do nothing;
  end if;

  return new;
end;
$$;
