import { supabase } from '../lib/supabase';

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
  return unwrap(await supabase.from('operational_alert_reads')
    .select('alert_key, fingerprint')
    .eq('company_id', companyId));
}

export async function markOperationalAlertRead(companyId, userId, alert) {
  return unwrap(await supabase.from('operational_alert_reads').upsert({
    company_id: companyId,
    user_id: userId,
    alert_key: alert.alert_key,
    fingerprint: alert.fingerprint,
    read_at: new Date().toISOString(),
  }, { onConflict: 'company_id,user_id,alert_key' }));
}
