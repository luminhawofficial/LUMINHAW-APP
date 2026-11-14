alter table public.plant_care
  add column if not exists water_requirements text,
  add column if not exists sunlight_requirements text,
  add column if not exists soil_requirements text;
