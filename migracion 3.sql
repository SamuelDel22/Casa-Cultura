-- Migración 3: jornada y asistencia. Ejecutar UNA vez (después de migracion_1 y 2), ANTES de publicar las páginas nuevas.
alter table students add column if not exists jornada text check (jornada in ('mañana','tarde'));

create table if not exists attendance(
 student_id uuid not null references students on delete cascade,
 activity_id uuid references activities,
 fecha date not null check (fecha <= current_date),
 presente boolean not null,
 marked_by uuid default auth.uid(), created_at timestamptz default now(),
 primary key(student_id, fecha));
create index if not exists att_act_fecha on attendance(activity_id, fecha);
create or replace function my_student(s uuid) returns boolean language sql security definer stable set search_path=public as $$ select exists(select 1 from students where id=s and my_activity(activity_id)) $$;
alter table attendance enable row level security;
create policy att_admin on attendance for all using (is_admin()) with check (is_admin());
create policy att_teacher on attendance for all using (my_student(student_id)) with check (my_student(student_id));

create or replace function register_student(p jsonb) returns text language plpgsql security definer set search_path=public as $$
declare c text; f date := (p->>'fecha_nacimiento')::date; act uuid := (p->>'activity_id')::uuid; docn text := trim(coalesce(p->>'doc_numero','')); arch jsonb := coalesce(p->'archivos','[]'::jsonb); fo text := nullif(p->>'foto',''); jor text := lower(trim(coalesce(p->>'jornada','')));
begin
 if coalesce(p->>'consentimiento','')<>'true' then raise exception 'CONSENTIMIENTO'; end if;
 if f > current_date or f < current_date - interval '30 years' then raise exception 'FECHA'; end if;
 if docn='' or coalesce(trim(p->>'doc_tipo'),'')='' then raise exception 'DOCUMENTO'; end if;
 if jor not in ('mañana','tarde') then raise exception 'JORNADA'; end if;
 if exists(select 1 from activities where id=act and pide_instrumento) and coalesce(trim(p->>'instrumento'),'')='' then raise exception 'INSTRUMENTO'; end if;
 if jsonb_array_length(arch)>3 or exists(select 1 from jsonb_array_elements_text(arch) x where x not like 'registro/%') or (fo is not null and fo not like 'registro/%') then raise exception 'ARCHIVO'; end if;
 if exists(select 1 from students where doc_numero=docn or (lower(nombres)=lower(trim(p->>'nombres')) and lower(apellidos)=lower(trim(p->>'apellidos')) and fecha_nacimiento=f)) then raise exception 'DUPLICADO'; end if;
 c := 'CC-'||upper(substr(md5(random()::text||clock_timestamp()::text),1,6));
 insert into students(code,nombres,apellidos,fecha_nacimiento,doc_tipo,doc_numero,colegio,grado,barrio,acudiente_nombre,acudiente_telefono,acudiente_email,activity_id,jornada,instrumento,archivos,foto,consent_at,consent_version)
 values(c,trim(p->>'nombres'),trim(p->>'apellidos'),f,trim(p->>'doc_tipo'),docn,trim(p->>'colegio'),trim(p->>'grado'),nullif(trim(p->>'barrio'),''),trim(p->>'acudiente_nombre'),trim(p->>'acudiente_telefono'),nullif(trim(p->>'acudiente_email'),''),act,jor,nullif(trim(p->>'instrumento'),''),array(select jsonb_array_elements_text(arch)),fo,now(),'v0-borrador');
 return c;
end $$;
