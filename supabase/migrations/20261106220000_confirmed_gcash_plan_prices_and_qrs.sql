alter table public.payment_plans
  add column if not exists qr_storage_path text;

update public.payment_plans
set amount_centavos = 4900,
    description = 'Premium access for 30 days.',
    qr_storage_path = 'plans/GCash-MyQR-49.PNG.jpg',
    updated_at = now()
where code = 'premium_30_days';

update public.payment_plans
set amount_centavos = 149900,
    description = 'Premium access for 365 days.',
    qr_storage_path = 'plans/GCash-MyQR-1499.PNG.jpg',
    updated_at = now()
where code = 'premium_365_days';

do $$
begin
  if not exists (
    select 1 from public.payment_plans where code = 'premium_30_days'
  ) or not exists (
    select 1 from public.payment_plans where code = 'premium_365_days'
  ) then
    raise exception
      'Expected Premium payment plans are missing; review the migration history before applying confirmed prices.';
  end if;
end;
$$;
