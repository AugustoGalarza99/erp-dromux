-- Dromux 031 · costos en dólares y proveedores en altas/importación.
-- Ejecutar una vez, después de 030. No modifica stock, fórmulas ni historial.
begin;

alter table public.items
  add column reference_cost_usd numeric(14,2),
  add column reference_exchange_rate_type_id uuid,
  add constraint items_reference_usd_pair check (
    (reference_cost_usd is null and reference_exchange_rate_type_id is null)
    or (reference_cost_usd is not null and reference_cost_usd>=0
      and reference_exchange_rate_type_id is not null)),
  add constraint items_reference_fx_company_fk foreign key(company_id,reference_exchange_rate_type_id)
    references public.exchange_rate_types(company_id,id);

-- Solo las funciones autorizadas escriben la fuente en USD. SELECT ya está concedido.
create or replace function private.sync_preferred_material_cost(p_company uuid,p_item uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_quote public.supplier_items%rowtype; v_rate numeric; v_cost numeric;
begin
  select * into v_quote from public.supplier_items
    where company_id=p_company and item_id=p_item and preferred;
  if not found then return; end if;
  if v_quote.currency_code='USD' then
    v_rate:=private.current_fx_rate(p_company,v_quote.exchange_rate_type_id);
    if v_rate is null then raise exception 'Cargá una cotización vigente para el tipo de dólar seleccionado'; end if;
  else v_rate:=1; end if;
  v_cost:=round(v_quote.unit_price*v_rate*(1+v_quote.adjustment_percent/100),2);
  -- El proveedor principal pasa a ser la única fuente de costo.
  update public.items set reference_unit_cost=v_cost,reference_cost_usd=null,
    reference_exchange_rate_type_id=null
    where company_id=p_company and id=p_item and
      (reference_unit_cost is distinct from v_cost or reference_cost_usd is not null);
end; $$;

create or replace function private.refresh_fx_costs()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_item record;
begin
  for v_item in select si.item_id from public.supplier_items si
    where si.company_id=new.company_id and si.exchange_rate_type_id=new.type_id and si.preferred loop
    perform private.sync_preferred_material_cost(new.company_id,v_item.item_id);
  end loop;
  update public.items i
    set reference_unit_cost=round(i.reference_cost_usd*private.current_fx_rate(i.company_id,new.type_id),2)
    where i.company_id=new.company_id and i.reference_exchange_rate_type_id=new.type_id
      and i.reference_cost_usd is not null and not exists(select 1 from public.supplier_items q
        where q.company_id=i.company_id and q.item_id=i.id and q.preferred);
  return new;
end; $$;

-- Evita que una escritura directa deje un costo en pesos y una fuente USD incompatibles.
create function private.check_reference_fx_cost() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_rate numeric;
begin
  if new.reference_cost_usd is not null then
    if not exists(select 1 from public.exchange_rate_types t where t.company_id=new.company_id
      and t.id=new.reference_exchange_rate_type_id and t.active) then
      raise exception 'Elegí un tipo de dólar activo';
    end if;
    v_rate:=private.current_fx_rate(new.company_id,new.reference_exchange_rate_type_id);
    if v_rate is null then raise exception 'Cargá una cotización vigente para ese tipo de dólar'; end if;
    new.reference_unit_cost:=round(new.reference_cost_usd*v_rate,2);
  end if;
  return new;
end; $$;
create trigger items_reference_fx_cost before insert or update of reference_unit_cost,
  reference_cost_usd,reference_exchange_rate_type_id on public.items
  for each row execute function private.check_reference_fx_cost();
revoke all on function private.check_reference_fx_cost() from public,anon,authenticated;

create function private.prepare_item_import(p_company uuid,p_rows jsonb,p_existing uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_row jsonb; v_index integer:=0; v_unit uuid; v_category uuid;
  v_code text; v_name text; v_type text; v_barcode text;
  v_cost numeric; v_price numeric; v_min numeric; v_lots boolean;
  v_infinite boolean; v_active boolean; v_description text;
  v_supplier uuid; v_fx_type uuid; v_usd numeric; v_rate numeric; v_matches integer;
  v_supplier_name text; v_fx_name text;
  v_result jsonb := '[]'::jsonb; v_codes text[] := '{}'; v_barcodes text[] := '{}';
begin
  if auth.uid() is null or not private.has_permission(p_company,'items',case when p_existing is null then 'insert' else 'update' end) then
    raise exception 'No tenés permiso para importar ítems' using errcode='42501';
  end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa no está activa'; end if;
  if p_rows is null or jsonb_typeof(p_rows)<>'array'
    or jsonb_array_length(p_rows) not between 1 and 200 then
    raise exception 'Importá entre 1 y 200 ítems por archivo';
  end if;
  if p_existing is not null and jsonb_array_length(p_rows)<>1 then
    raise exception 'La edición debe contener un solo ítem';
  end if;
  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_index:=v_index+1;
    if jsonb_typeof(v_row)<>'object' then
      raise exception 'Fila %: formato inválido',v_index+1;
    end if;
    v_code:=btrim(coalesce(v_row->>'codigo',''));
    v_name:=btrim(coalesce(v_row->>'nombre',''));
    v_type:=btrim(coalesce(v_row->>'tipo',''));
    v_barcode:=nullif(btrim(coalesce(v_row->>'codigo_barras','')),'');
    v_description:=btrim(coalesce(v_row->>'descripcion',''));
    if v_code !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$'
      or length(v_name) not between 2 and 160
      or v_type not in ('raw_material','semi_finished','finished_product','consumable')
      or length(v_description)>1500
      or (v_barcode is not null and length(v_barcode) not between 4 and 80) then
      raise exception 'Fila %: revisá código, nombre, tipo, descripción y código de barras',v_index+1;
    end if;
    if coalesce(v_row->>'stock_minimo','') !~ '^\d+(\.\d{1,6})?$'
      or coalesce(v_row->>'costo_referencia_ars','') !~ '^\d+(\.\d{1,2})?$'
      and nullif(v_row->>'costo_referencia_ars','') is not null
      or coalesce(v_row->>'precio_venta_ars','') !~ '^\d+(\.\d{1,2})?$'
      and nullif(v_row->>'precio_venta_ars','') is not null then
      raise exception 'Fila %: números inválidos (usá punto decimal)',v_index+1;
    end if;
    v_min:=(v_row->>'stock_minimo')::numeric;
    v_cost:=nullif(v_row->>'costo_referencia_ars','')::numeric;
    v_price:=nullif(v_row->>'precio_venta_ars','')::numeric;
    if v_min>=1000000000000 or coalesce(v_cost,0)>=1000000000000
      or coalesce(v_price,0)>=1000000000000 then
      raise exception 'Fila %: importe o cantidad fuera de rango',v_index+1;
    end if;
    if coalesce(v_row->>'seguir_lotes','') not in ('true','false')
      or coalesce(v_row->>'stock_infinito','') not in ('true','false')
      or coalesce(v_row->>'activo','') not in ('true','false') then
      raise exception 'Fila %: usá SI o NO en las columnas de opciones',v_index+1;
    end if;
    v_lots:=(v_row->>'seguir_lotes')::boolean;
    v_infinite:=(v_row->>'stock_infinito')::boolean;
    v_active:=(v_row->>'activo')::boolean;
    if v_infinite and (v_lots or v_min<>0) then
      raise exception 'Fila %: stock infinito requiere sin lotes y stock mínimo cero',v_index+1;
    end if;
    if v_price is not null and (v_type<>'finished_product'
      or private.get_user_role(p_company)<>'admin'
      or not private.has_permission(p_company,'sales','update')) then
      raise exception 'Fila %: solo un administrador puede cargar precios de productos terminados',v_index+1;
    end if;
    v_supplier:=null; v_fx_type:=null; v_usd:=null; v_rate:=null;
    v_supplier_name:=nullif(btrim(coalesce(v_row->>'proveedor','')),'');
    v_fx_name:=nullif(btrim(coalesce(v_row->>'tipo_dolar','')),'');
    if nullif(btrim(coalesce(v_row->>'costo_usd','')),'') is not null then
      if btrim(v_row->>'costo_usd') !~ '^\d+(\.\d{1,2})?$' then
        raise exception 'Fila %: costo en dólares inválido, hasta dos decimales',v_index+1;
      end if;
      v_usd:=btrim(v_row->>'costo_usd')::numeric;
      if v_usd>=1000000000000 then raise exception 'Fila %: costo en dólares fuera de rango',v_index+1; end if;
      if v_fx_name is null then raise exception 'Fila %: indicá el tipo de dólar para el costo en dólares',v_index+1; end if;
    elsif v_fx_name is not null then
      raise exception 'Fila %: el tipo de dólar requiere un costo en dólares',v_index+1;
    end if;
    if v_fx_name is not null then
      select count(*), min(t.id::text)::uuid into v_matches,v_fx_type
        from public.exchange_rate_types t where t.company_id=p_company and t.active
          and lower(btrim(t.name))=lower(v_fx_name);
      if v_matches<>1 then raise exception 'Fila %: el tipo de dólar no existe, está inactivo o su nombre es ambiguo',v_index+1; end if;
      v_rate:=private.current_fx_rate(p_company,v_fx_type);
      if v_rate is null then raise exception 'Fila %: cargá una cotización vigente para %',v_index+1,v_fx_name; end if;
      v_cost:=round(v_usd*v_rate,2);
      if v_cost>=1000000000000 then raise exception 'Fila %: costo convertido fuera de rango',v_index+1; end if;
    end if;
    if v_supplier_name is not null then
      if not private.has_permission(p_company,'purchases','update') then
        raise exception 'Necesitás permiso para editar Compras para asociar proveedores' using errcode='42501';
      end if;
      select count(*),min(s.id::text)::uuid into v_matches,v_supplier from public.suppliers s
        where s.company_id=p_company and s.active and lower(btrim(s.name))=lower(v_supplier_name);
      if v_matches<>1 then raise exception 'Fila %: el proveedor no existe, está inactivo o su nombre es ambiguo',v_index+1; end if;
      if v_cost is null then raise exception 'Fila %: indicá un costo en pesos o dólares para asociar el proveedor',v_index+1; end if;
      if not v_active then raise exception 'Fila %: el ítem debe estar activo para asociar un proveedor',v_index+1; end if;
      if p_existing is not null and exists(select 1 from public.supplier_items q
        where q.company_id=p_company and q.item_id=p_existing and q.supplier_id=v_supplier) then
        raise exception 'Este ítem ya está asociado al proveedor. Editá su precio en Compras';
      end if;
    end if;
    if v_type='raw_material' and v_cost is null then
      raise exception 'Fila %: la materia prima necesita costo de referencia',v_index+1;
    end if;
    select u.id into v_unit from public.units u
      where u.company_id=p_company and u.active
        and lower(u.code)=lower(btrim(coalesce(v_row->>'unidad_codigo','')));
    if v_unit is null then
      raise exception 'Fila %: la unidad no existe o está inactiva',v_index+1;
    end if;
    v_category:=null;
    if nullif(btrim(coalesce(v_row->>'categoria_codigo','')),'') is not null then
      select c.id into v_category from public.item_categories c
        where c.company_id=p_company and c.active
          and lower(c.code)=lower(btrim(v_row->>'categoria_codigo'));
      if v_category is null then
        raise exception 'Fila %: la categoría no existe o está inactiva',v_index+1;
      end if;
    end if;
    if exists (select 1 from public.items i where i.company_id=p_company
      and i.id is distinct from p_existing and lower(i.code)=lower(v_code)) then
      raise exception 'Fila %: el código % ya existe o está repetido',v_index+1,v_code;
    end if;
    if v_barcode is not null and exists (select 1 from public.items i
      where i.company_id=p_company and i.id is distinct from p_existing and i.barcode=v_barcode) then
      raise exception 'Fila %: el código de barras % ya existe o está repetido',v_index+1,v_barcode;
    end if;
    if lower(v_code)=any(v_codes) or (v_barcode is not null and v_barcode=any(v_barcodes)) then
      raise exception 'Fila %: código o código de barras repetido en el archivo',v_index+1;
    end if;
    v_codes:=array_append(v_codes,lower(v_code));
    if v_barcode is not null then v_barcodes:=array_append(v_barcodes,v_barcode); end if;
    v_result:=v_result || jsonb_build_array(v_row || jsonb_build_object(
      'unit_id',v_unit,'category_id',v_category,'supplier_id',v_supplier,
      'exchange_type_id',v_fx_type,'cost_ars',v_cost,'cost_usd',v_usd,'exchange_rate',v_rate));
  end loop;
  return v_result;
end; $$;
revoke all on function private.prepare_item_import(uuid,jsonb,uuid) from public,anon,authenticated;

create function public.preview_item_import(p_company uuid,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  return private.prepare_item_import(p_company,p_rows);
end; $$;

create or replace function public.import_items(p_company uuid,p_rows jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare v_rows jsonb; v_row jsonb; v_id uuid; v_supplier uuid; v_fx uuid; v_usd numeric;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('import-items:'||p_company::text,0));
  v_rows:=private.prepare_item_import(p_company,p_rows);
  for v_row in select value from jsonb_array_elements(v_rows) loop
    v_supplier:=nullif(v_row->>'supplier_id','')::uuid;
    v_fx:=nullif(v_row->>'exchange_type_id','')::uuid;
    v_usd:=nullif(v_row->>'cost_usd','')::numeric;
    insert into public.items(company_id,code,name,item_type,category_id,unit_id,barcode,
      description,minimum_stock,track_lots,infinite_stock,reference_unit_cost,sale_unit_price,
      active,reference_cost_usd,reference_exchange_rate_type_id)
    values(p_company,btrim(v_row->>'codigo'),btrim(v_row->>'nombre'),v_row->>'tipo',
      nullif(v_row->>'category_id','')::uuid,(v_row->>'unit_id')::uuid,
      nullif(btrim(v_row->>'codigo_barras'),''),btrim(v_row->>'descripcion'),
      (v_row->>'stock_minimo')::numeric,(v_row->>'seguir_lotes')::boolean,
      (v_row->>'stock_infinito')::boolean,nullif(v_row->>'cost_ars','')::numeric,
      nullif(v_row->>'precio_venta_ars','')::numeric,(v_row->>'activo')::boolean,
      case when v_supplier is null then v_usd end,
      case when v_supplier is null then v_fx end) returning id into v_id;
    if v_supplier is not null then
      perform public.save_supplier_quote(p_company,v_supplier,v_id,
        coalesce(v_usd,(v_row->>'cost_ars')::numeric),'',
        case when v_usd is null then 'ARS' else 'USD' end,v_fx,0,null,true);
      perform public.set_preferred_supplier(p_company,v_id,v_supplier);
    end if;
  end loop;
  return jsonb_array_length(v_rows);
end; $$;

-- Formulario manual: ficha y nueva relación de proveedor en una sola transacción.
-- Las relaciones existentes se editan desde Compras y nunca se sobrescriben aquí.
create function public.save_item_with_cost(p_company uuid,p_item uuid,p_row jsonb,
  p_expected_updated_at timestamptz default null,p_preserve_cost boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.items%rowtype; v_row jsonb; v_supplier uuid; v_fx uuid; v_usd numeric;
  v_primary boolean; v_id uuid; v_unit_code text; v_category_code text;
begin
  if auth.uid() is null or not private.has_permission(p_company,'items',
    case when p_item is null then 'insert' else 'update' end) then
    raise exception 'Sin permiso para guardar el ítem' using errcode='42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('import-items:'||p_company::text,0));
  if p_item is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('preferred:'||p_company::text||':'||p_item::text,0));
    select * into v_old from public.items where company_id=p_company and id=p_item for update;
    if not found then raise exception 'El ítem no existe en esta empresa'; end if;
    if p_expected_updated_at is null or v_old.updated_at<>p_expected_updated_at then
      raise exception 'La ficha cambió mientras la editabas. Recargá antes de guardar'; end if;
  end if;
  -- El formulario selecciona IDs; Excel usa códigos/nombres. Resolverlos siempre en la empresa.
  select u.code into v_unit_code from public.units u
    where u.company_id=p_company and u.id=nullif(p_row->>'unit_id','')::uuid;
  select c.code into v_category_code from public.item_categories c
    where c.company_id=p_company and c.id=nullif(p_row->>'category_id','')::uuid;
  if nullif(p_row->>'category_id','') is not null and v_category_code is null then
    raise exception 'La categoría no pertenece a esta empresa'; end if;
  v_row:=p_row || jsonb_build_object('unidad_codigo',v_unit_code,'categoria_codigo',coalesce(v_category_code,''));
  if nullif(p_row->>'supplier_id','') is not null then
    select s.name into v_unit_code from public.suppliers s where s.company_id=p_company
      and s.id=(p_row->>'supplier_id')::uuid and s.active;
    if not found then raise exception 'Elegí un proveedor activo de esta empresa'; end if;
    v_row:=v_row || jsonb_build_object('proveedor',v_unit_code);
  end if;
  if nullif(p_row->>'exchange_type_id','') is not null then
    select t.name into v_unit_code from public.exchange_rate_types t where t.company_id=p_company
      and t.id=(p_row->>'exchange_type_id')::uuid and t.active;
    if not found then raise exception 'Elegí un tipo de dólar activo de esta empresa'; end if;
    v_row:=v_row || jsonb_build_object('tipo_dolar',v_unit_code);
  end if;
  select exists(select 1 from public.supplier_items q where q.company_id=p_company
    and q.item_id=p_item and q.preferred) into v_primary;
  if p_item is not null and (p_preserve_cost or v_primary) and nullif(p_row->>'supplier_id','') is null then
    v_row:=v_row || jsonb_build_object('costo_referencia_ars',v_old.reference_unit_cost,
      'costo_usd','','tipo_dolar','');
  end if;
  v_row:=private.prepare_item_import(p_company,jsonb_build_array(v_row),p_item)->0;
  v_supplier:=nullif(v_row->>'supplier_id','')::uuid;
  v_fx:=nullif(v_row->>'exchange_type_id','')::uuid;
  v_usd:=nullif(v_row->>'cost_usd','')::numeric;
  if p_item is null then
    -- Importación de una fila reutiliza las mismas reglas y triggers.
    perform public.import_items(p_company,jsonb_build_array(v_row));
    select id into v_id from public.items where company_id=p_company and code=btrim(v_row->>'codigo');
    return v_id;
  end if;
  update public.items set code=btrim(v_row->>'codigo'),name=btrim(v_row->>'nombre'),
    item_type=v_row->>'tipo',category_id=nullif(v_row->>'category_id','')::uuid,
    unit_id=(v_row->>'unit_id')::uuid,barcode=nullif(btrim(v_row->>'codigo_barras'),''),
    description=btrim(v_row->>'descripcion'),minimum_stock=(v_row->>'stock_minimo')::numeric,
    track_lots=(v_row->>'seguir_lotes')::boolean,infinite_stock=(v_row->>'stock_infinito')::boolean,
    reference_unit_cost=case when v_primary or p_preserve_cost then v_old.reference_unit_cost else nullif(v_row->>'cost_ars','')::numeric end,
    reference_cost_usd=case when v_primary or p_preserve_cost then v_old.reference_cost_usd
      when v_supplier is null then v_usd end,
    reference_exchange_rate_type_id=case when v_primary or p_preserve_cost then v_old.reference_exchange_rate_type_id
      when v_supplier is null then v_fx end
    where company_id=p_company and id=p_item;
  if v_supplier is not null then
    perform public.save_supplier_quote(p_company,v_supplier,p_item,
      coalesce(v_usd,(v_row->>'cost_ars')::numeric),'',
      case when v_usd is null then 'ARS' else 'USD' end,v_fx,0,null,true);
    if not v_primary then perform public.set_preferred_supplier(p_company,p_item,v_supplier); end if;
  end if;
  return p_item;
end; $$;

create function public.item_cost_context(p_company uuid,p_item uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'items','read')
    or not private.has_permission(p_company,'purchases','read') then
    raise exception 'Sin acceso a los costos del proveedor' using errcode='42501'; end if;
  return (select jsonb_build_object('supplier_id',q.supplier_id,'supplier_name',s.name,
    'currency_code',q.currency_code,'unit_price',q.unit_price)
    from public.supplier_items q join public.suppliers s on s.company_id=q.company_id and s.id=q.supplier_id
    where q.company_id=p_company and q.item_id=p_item and q.preferred);
end; $$;

revoke all on function public.preview_item_import(uuid,jsonb),
  public.save_item_with_cost(uuid,uuid,jsonb,timestamptz,boolean),
  public.item_cost_context(uuid,uuid) from public,anon;
grant execute on function public.preview_item_import(uuid,jsonb),
  public.save_item_with_cost(uuid,uuid,jsonb,timestamptz,boolean),
  public.item_cost_context(uuid,uuid) to authenticated;
commit;
