create or replace function public.create_company(p_name text)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_company uuid;
  v_role uuid;
  v_user uuid := auth.uid();
  v_name text := nullif(btrim(p_name), '');
begin
  if v_user is null then raise exception 'Iniciá sesión' using errcode = '42501'; end if;
  if v_name is null or length(v_name) not between 2 and 100 then
    raise exception 'El nombre debe tener entre 2 y 100 caracteres';
  end if;
  insert into public.empresas(nombre, identificador)
    values (v_name, 'empresa-' || replace(gen_random_uuid()::text, '-', ''))
    returning id into v_company;
  insert into public.ajustes_roles(empresa_id, codigo, nombre)
    values (v_company, 'administrador', 'Administrador') returning id into v_role;
  insert into public.empresas_usuarios(empresa_id, usuario_id, rol_id) values (v_company, v_user, v_role);
  insert into public.ajustes_roles_permisos(empresa_id, rol_id, recurso, accion)
  select v_company, v_role, c.recurso, a.accion
  from public.ajustes_permisos_catalogo c cross join lateral unnest(c.acciones) as a(accion);
  insert into public.ajustes_perfiles(id, nombre)
    values (v_user, coalesce(nullif(v_user::text, ''), 'Usuario'))
    on conflict (id) do nothing;
  return v_company;
end
$function$
