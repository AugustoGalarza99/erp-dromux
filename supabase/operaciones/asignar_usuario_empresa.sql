-- Ejecutar en SQL Editor con permisos de administrador DESPUÉS de crear
-- el usuario desde Authentication → Users (no crear auth.users por SQL).
-- Cambiá SOLAMENTE estas tres variables. Podés repetir el bloque:
-- asigna el rol indicado y activa la membresía sin crear duplicados.

do $$
declare
  v_email text := lower(btrim('usuario@empresa.com'));
  v_company uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_role_code text := 'operador';
  v_user uuid;
  v_role uuid;
begin
  select u.id into v_user
  from auth.users u
  where lower(u.email) = v_email;
  if v_user is null then
    raise exception 'No existe el usuario %. Crealo primero en Authentication → Users', v_email;
  end if;

  if not exists (
    select 1 from public.companies c where c.id = v_company and c.active
  ) then
    raise exception 'La empresa no existe o está suspendida';
  end if;

  select r.id into v_role
  from public.roles r
  where r.company_id = v_company and r.code = v_role_code;
  if v_role is null then
    raise exception 'La empresa no tiene un rol con código %', v_role_code;
  end if;

  insert into public.profiles(id, name)
  values (v_user, split_part(v_email, '@', 1))
  on conflict (id) do nothing;

  insert into public.company_users(company_id, user_id, role_id, active)
  values (v_company, v_user, v_role, true)
  on conflict (company_id, user_id)
  do update set role_id = excluded.role_id, active = true;

  raise notice 'Usuario % asignado a la empresa % con rol %',
    v_email, v_company, v_role_code;
end;
$$;

-- Comprobación: reemplazá el mismo correo antes de ejecutar.
select u.email, c.name as empresa, r.name as rol, cu.active
from public.company_users cu
join auth.users u on u.id = cu.user_id
join public.companies c on c.id = cu.company_id
join public.roles r on r.id = cu.role_id and r.company_id = cu.company_id
where lower(u.email) = lower(btrim('usuario@empresa.com'));
