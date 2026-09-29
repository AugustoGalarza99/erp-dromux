import { supabase } from '../lib/supabase';

export async function getReplenishmentForecast(companyId) {
  const { data, error } = await supabase.rpc('erp_replenishment_forecast', {
    p_company: companyId,
  });

  if (error) throw error;
  return data ?? [];
}
