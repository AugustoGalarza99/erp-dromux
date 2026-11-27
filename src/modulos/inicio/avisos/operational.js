import { supabase } from '../../../compartido/utilidades/supabase';

function unwrap({ data, error }) {
  if (error) throw error;
  return data;
}

export async function listOperationalAlerts(companyId) {
  return unwrap(await supabase.rpc('erp_production_alerts', {
    p_company: companyId,
  }));
}

export async function listReadAlerts(companyId) {
  return unwrap(await supabase.from('inicio_alertas_leidas')
    .select('alert_key:alerta_clave, fingerprint:huella')
    .eq('empresa_id', companyId));
}

export async function markOperationalAlertRead(companyId, userId, alert) {
  return unwrap(await supabase.from('inicio_alertas_leidas').upsert({
    empresa_id: companyId,
    usuario_id: userId,
    alerta_clave: alert.alert_key,
    huella: alert.fingerprint,
    leido_en: new Date().toISOString(),
  }, { onConflict: 'empresa_id,usuario_id,alerta_clave' }));
}
