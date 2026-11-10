update public.payment_plans
set amount_centavos = 49900,
    description = 'Premium access for 365 days.',
    qr_storage_path = 'plans/GCash-MyQR-499.PNG.jpg',
    updated_at = now()
where code = 'premium_365_days';

do $$
begin
  if not exists (
    select 1
    from public.payment_plans
    where code = 'premium_365_days'
      and amount_centavos = 49900
      and currency = 'PHP'
      and duration_days = 365
      and qr_storage_path = 'plans/GCash-MyQR-499.PNG.jpg'
  ) then
    raise exception
      'The 365-day Premium plan was not updated to PHP 499 with its matching QR path.';
  end if;
end;
$$;
