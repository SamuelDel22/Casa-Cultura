-- Migración 4: opciones de filtros y rendimiento de la lista. Ejecutar UNA vez.
create or replace function filter_options() returns jsonb language sql stable security invoker set search_path=public as $$
 select jsonb_build_object(
  'colegios', coalesce((select jsonb_agg(c order by c) from (select distinct colegio c from students) t),'[]'::jsonb),
  'grados',   coalesce((select jsonb_agg(g order by g) from (select distinct grado g from students) t),'[]'::jsonb)) $$;
grant execute on function filter_options() to authenticated;
create index if not exists students_created on students(created_at desc);
