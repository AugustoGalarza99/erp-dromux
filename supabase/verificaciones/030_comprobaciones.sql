-- Sólo lectura. Ejecutar después de 030 para verificar la instalación.
select column_name,data_type,character_maximum_length
from information_schema.columns where table_schema='public'
  and table_name='suppliers' and column_name='supplies_description';

select signature,to_regprocedure(signature) is not null as instalado
from (values
 ('public.supplier_directory(uuid,text,integer)'),
 ('public.supplier_quote_catalog(uuid,uuid,uuid,text,integer)'),
 ('public.save_supplier_quote(uuid,uuid,uuid,numeric,text,text,uuid,numeric,timestamptz,boolean)'),
 ('public.supplier_adjustment_preview(uuid,uuid,uuid,numeric)'),
 ('public.exchange_rate_overview(uuid)'),
 ('public.add_exchange_rate(uuid,uuid,numeric,date)')
) f(signature);

-- Debe conservar exchange_rates_immutable.
select tgname from pg_catalog.pg_trigger where tgrelid='public.exchange_rates'::regclass
  and not tgisinternal order by tgname;

-- No debe existir la restricción única de cuatro columnas (valor + fecha).
-- Sí se conservan las claves únicas de identidad.
select conname,pg_catalog.pg_get_constraintdef(oid)
from pg_catalog.pg_constraint where conrelid='public.exchange_rates'::regclass and contype='u';
