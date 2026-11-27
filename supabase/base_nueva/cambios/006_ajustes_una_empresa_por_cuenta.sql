-- 006 · Una cuenta puede crear empresa solo si no está vinculada a ninguna.
-- La pantalla ya lo hacía; ahora lo exige la base. Cuenta cualquier vínculo: activo o no, y
-- aunque la empresa esté suspendida.
begin;

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
  -- Dos pedidos simultáneos de la misma cuenta se atienden de a uno.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('alta-empresa:' || v_user::text, 0));
  if exists (select 1 from public.empresas_usuarios m where m.usuario_id = v_user) then
    raise exception 'Tu cuenta ya pertenece a una empresa. Ingresá a esa empresa o pedí ayuda a soporte';
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
    select v_user, coalesce(
      nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
      nullif(split_part(u.email, '@', 1), ''),
      'Usuario'
    )
    from auth.users u
    where u.id = v_user
    on conflict (id) do nothing;
  return v_company;
end
$function$;

commit;
