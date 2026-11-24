-- Deshace 041 (presupuestos y datos de la empresa). Aborta si ya hay presupuestos o datos de empresa
-- cargados: exportalos antes. No toca ventas, stock ni listas de precios.
begin;

do $$
begin
  if exists (select 1 from public.quotes) or exists (select 1 from public.quote_lines)
     or exists (select 1 from public.quote_status_events) then
    raise exception 'Hay presupuestos cargados. Exportalos antes de deshacer la migración 041.';
  end if;
  if exists (select 1 from public.company_profile where legal_name <> '' or tax_id <> '' or address <> ''
             or phone <> '' or email <> '' or website <> '' or tax_condition <> ''
             or logo_data is distinct from coalesce((select s.logo_data from public.production_document_settings s
                  where s.company_id = company_profile.company_id), '')) then
    raise exception 'Hay datos de empresa cargados (CUIT, domicilio, contacto). Anotalos antes de deshacer la 041.';
  end if;
end
$$;

drop function if exists public.erp_quote_detail(uuid, uuid);
drop function if exists public.erp_quotes_page(uuid, text, text, integer, integer);
drop function if exists public.set_quote_status(uuid, uuid, text);
drop function if exists public.create_quote(uuid, uuid, text, text, text, text, text, date, text, boolean, jsonb, uuid);
drop function if exists public.erp_company_profile(uuid);
drop function if exists public.save_company_profile(uuid, text, text, text, text, text, text, text, text);

drop table if exists public.quote_status_events;
drop table if exists public.quote_lines;
drop table if exists public.quotes;
drop table if exists public.quote_counters;
-- El logo copiado en company_profile se descarta (el original sigue en production_document_settings).
drop table if exists public.company_profile;

drop function if exists private.quotes_guard();
drop function if exists private.quote_lines_immutable();

commit;
