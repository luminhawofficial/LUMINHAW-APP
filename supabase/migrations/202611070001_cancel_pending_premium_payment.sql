create function public.cancel_pending_premium_payment_request(
  p_user_id uuid,
  p_payment_request_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_request public.premium_payment_requests%rowtype;
begin
  if p_user_id is null or p_payment_request_id is null then
    raise exception 'Invalid payment request.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text, 0)
  );

  select * into current_request
  from public.premium_payment_requests
  where id = p_payment_request_id and user_id = p_user_id
  for update;

  if not found or current_request.payment_status <> 'pending' then
    return false;
  end if;

  update public.premium_payment_requests
  set payment_status = 'cancelled',
      updated_at = pg_catalog.clock_timestamp()
  where id = current_request.id;

  insert into public.premium_payment_events (
    payment_request_id, actor_id, previous_status, new_status, event_type
  )
  values (
    current_request.id,
    p_user_id,
    'pending',
    'cancelled',
    'customer_cancelled_request'
  );

  return true;
end;
$$;

revoke all on function public.cancel_pending_premium_payment_request(
  uuid, uuid
) from public, anon, authenticated;
grant execute on function public.cancel_pending_premium_payment_request(
  uuid, uuid
) to service_role;
