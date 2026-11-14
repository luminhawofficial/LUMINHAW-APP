begin;

select plan(6);

select ok(
  has_column('public', 'plant_catalog', 'field_references')
    and has_column('public', 'plant_catalog', 'date_updated'),
  'catalog reference and date fields exist'
);

select ok(
  has_column('public', 'plant_care', 'fertilizer')
    and has_column('public', 'plant_care', 'growth_tips')
    and has_column('public', 'plant_care', 'common_diseases')
    and has_column('public', 'plant_care', 'treatment')
    and has_column('public', 'plant_care', 'toxicity'),
  'admin care fields exist'
);

select ok(
  to_regprocedure(
    'public.admin_save_plant_catalog(uuid,uuid,jsonb,jsonb,jsonb,text,text,date)'
  ) is not null,
  'transactional catalog save function exists'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.admin_save_plant_catalog(uuid,uuid,jsonb,jsonb,jsonb,text,text,date)',
    'EXECUTE'
  ),
  'only the service role can invoke catalog save'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.admin_save_plant_catalog(uuid,uuid,jsonb,jsonb,jsonb,text,text,date)',
    'EXECUTE'
  ),
  'authenticated clients cannot invoke catalog save directly'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_save_plant_catalog(uuid,uuid,jsonb,jsonb,jsonb,text,text,date)',
    'EXECUTE'
  ),
  'anonymous clients cannot invoke catalog save'
);

select * from finish();

rollback;
