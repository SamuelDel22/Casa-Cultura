-- Migración 1: documento, instrumento y archivos. Ejecutar UNA vez en SQL Editor.
alter table activities add column if not exists pide_instrumento boolean default false;
update activities set pide_instrumento=true where name='Música';
alter table students add column if not exists doc_tipo text, add column if not exists doc_numero text, add column if not exists instrumento text, add column if not exists archivos text[] default '{}';
create unique index if not exists students_doc_unico on students(doc_numero) where doc_numero is not null;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('documentos','documentos',false,5242880,array['image/jpeg','image/png','image/webp','application/pdf']) on conflict (id) do nothing;
create policy doc_subir on storage.objects for insert to anon, authenticated with check (bucket_id='documentos' and name like 'registro/%');
create policy doc_ver on storage.objects for select to authenticated using (bucket_id='documentos' and (is_admin() or exists(select 1 from students s where storage.objects.name = any(s.archivos) and my_activity(s.activity_id))));
create policy doc_borrar on storage.objects for delete to authenticated using (bucket_id='documentos' and is_admin());

create or replace function register_student(p jsonb) returns text language plpgsql security definer set search_path=public as $$
declare c text; f date := (p->>'fecha_nacimiento')::date; act uuid := (p->>'activity_id')::uuid; docn text := trim(coalesce(p->>'doc_numero','')); arch jsonb := coalesce(p->'archivos','[]'::jsonb);
begin
 if coalesce(p->>'consentimiento','')<>'true' then raise exception 'CONSENTIMIENTO'; end if;
 if f > current_date or f < current_date - interval '30 years' then raise exception 'FECHA'; end if;
 if docn='' or coalesce(trim(p->>'doc_tipo'),'')='' then raise exception 'DOCUMENTO'; end if;
 if exists(select 1 from activities where id=act and pide_instrumento) and coalesce(trim(p->>'instrumento'),'')='' then raise exception 'INSTRUMENTO'; end if;
 if jsonb_array_length(arch)>3 or exists(select 1 from jsonb_array_elements_text(arch) x where x not like 'registro/%') then raise exception 'ARCHIVO'; end if;
 if exists(select 1 from students where doc_numero=docn or (lower(nombres)=lower(trim(p->>'nombres')) and lower(apellidos)=lower(trim(p->>'apellidos')) and fecha_nacimiento=f)) then raise exception 'DUPLICADO'; end if;
 c := 'CC-'||upper(substr(md5(random()::text||clock_timestamp()::text),1,6));
 insert into students(code,nombres,apellidos,fecha_nacimiento,doc_tipo,doc_numero,colegio,grado,barrio,acudiente_nombre,acudiente_telefono,acudiente_email,activity_id,instrumento,archivos,consent_at,consent_version)
 values(c,trim(p->>'nombres'),trim(p->>'apellidos'),f,trim(p->>'doc_tipo'),docn,trim(p->>'colegio'),trim(p->>'grado'),nullif(trim(p->>'barrio'),''),trim(p->>'acudiente_nombre'),trim(p->>'acudiente_telefono'),nullif(trim(p->>'acudiente_email'),''),act,nullif(trim(p->>'instrumento'),''),array(select jsonb_array_elements_text(arch)),now(),'v0-borrador');
 return c;
end $$;
