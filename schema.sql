-- CAUCE · esquema Supabase/PostgreSQL. Ejecutar completo en SQL Editor.
create table profiles(id uuid primary key references auth.users on delete cascade, full_name text, role text not null default 'teacher' check (role in ('admin','teacher')), created_at timestamptz default now());
create table activities(id uuid primary key default gen_random_uuid(), name text unique not null, active boolean default true);
create table activity_teachers(activity_id uuid references activities on delete cascade, teacher_id uuid references profiles on delete cascade, primary key(activity_id,teacher_id));
create table students(
 id uuid primary key default gen_random_uuid(), code text unique not null,
 nombres text not null, apellidos text not null, fecha_nacimiento date not null,
 colegio text not null, grado text not null, barrio text,
 acudiente_nombre text not null, acudiente_telefono text not null, acudiente_email text,
 activity_id uuid references activities, status text not null default 'pendiente' check (status in ('activo','inactivo','pendiente')),
 consent_at timestamptz not null, consent_version text not null, created_at timestamptz default now());
create index on students(activity_id); create index on students(status);

create function is_admin() returns boolean language sql security definer stable set search_path=public as $$ select exists(select 1 from profiles where id=auth.uid() and role='admin') $$;
create function is_staff() returns boolean language sql security definer stable set search_path=public as $$ select exists(select 1 from profiles where id=auth.uid()) $$;
create function my_activity(a uuid) returns boolean language sql security definer stable set search_path=public as $$ select exists(select 1 from activity_teachers where activity_id=a and teacher_id=auth.uid()) $$;

create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into profiles(id,full_name) values(new.id, coalesce(new.raw_user_meta_data->>'full_name',new.email)); return new; end $$;
create trigger on_auth_user after insert on auth.users for each row execute function handle_new_user();

-- Registro público: sin acceso directo a la tabla; solo esta función.
create function register_student(p jsonb) returns text language plpgsql security definer set search_path=public as $$
declare c text; f date := (p->>'fecha_nacimiento')::date;
begin
 if coalesce(p->>'consentimiento','')<>'true' then raise exception 'CONSENTIMIENTO'; end if;
 if f > current_date or f < current_date - interval '30 years' then raise exception 'FECHA'; end if;
 if exists(select 1 from students where lower(nombres)=lower(trim(p->>'nombres')) and lower(apellidos)=lower(trim(p->>'apellidos')) and fecha_nacimiento=f) then raise exception 'DUPLICADO'; end if;
 c := 'CC-'||upper(substr(md5(random()::text||clock_timestamp()::text),1,6));
 insert into students(code,nombres,apellidos,fecha_nacimiento,colegio,grado,barrio,acudiente_nombre,acudiente_telefono,acudiente_email,activity_id,consent_at,consent_version)
 values(c,trim(p->>'nombres'),trim(p->>'apellidos'),f,trim(p->>'colegio'),trim(p->>'grado'),nullif(trim(p->>'barrio'),''),trim(p->>'acudiente_nombre'),trim(p->>'acudiente_telefono'),nullif(trim(p->>'acudiente_email'),''),(p->>'activity_id')::uuid,now(),'v0-borrador');
 return c;
end $$;
revoke all on function register_student(jsonb) from public; grant execute on function register_student(jsonb) to anon, authenticated;

alter table profiles enable row level security; alter table activities enable row level security;
alter table activity_teachers enable row level security; alter table students enable row level security;
create policy prof_self on profiles for select using (id=auth.uid() or is_admin());
create policy prof_admin on profiles for all using (is_admin()) with check (is_admin());
create policy act_read on activities for select using (active or is_staff());
create policy act_admin on activities for all using (is_admin()) with check (is_admin());
create policy at_read on activity_teachers for select using (teacher_id=auth.uid() or is_admin());
create policy at_admin on activity_teachers for all using (is_admin()) with check (is_admin());
create policy st_admin on students for all using (is_admin()) with check (is_admin());
create policy st_teacher_read on students for select using (my_activity(activity_id));
create policy st_teacher_upd on students for update using (my_activity(activity_id)) with check (my_activity(activity_id));

insert into activities(name) values ('Música'),('Danza'),('Teatro'),('Artes plásticas'),('Literatura'),('Cultura'),('Otro');
