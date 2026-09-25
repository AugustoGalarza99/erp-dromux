import { toast } from 'sonner';

export function friendlyError(error) {
  const message = error?.message || 'No se pudo completar la operación.';

  if (message.includes('No se puede activar lotes en un ítem con historial')) {
    return 'Aplicá la migración SQL 007 para activar lotes en un ítem con historial.';
  }

  if (message.includes('El ítem tiene stock sin lotes')) {
    return 'Aplicá la migración 007 y activá lotes desde la ficha para crear saldos iniciales auditados.';
  }

  if (error?.code === '23505') {
    return 'Ya existe un registro con esos datos. Revisá el código y volvé a intentar.';
  }

  return message;
}

export function notifySuccess(message, description) {
  toast.success(message, { description });
}

export function notifyError(error) {
  const message = friendlyError(error);
  toast.error('No se pudo completar la acción', { description: message, duration: 6500 });
  return message;
}
