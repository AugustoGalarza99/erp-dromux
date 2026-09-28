import { toast } from 'sonner';

export function friendlyError(error) {
  const message = error?.message || 'No se pudo completar la operación.';

  if (/Invalid login credentials|Email not confirmed/i.test(message)) {
    return 'Revisá tu correo y contraseña, o pedí ayuda al administrador.';
  }

  if (error?.code === '23505') {
    return 'Ya existe un registro con esos datos. Revisá el código y volvé a intentar.';
  }

  if (/permission denied|row-level security|PGRST|function public\.|relation public\.|JWT|fetch failed|Failed to fetch/i.test(message)) {
    return 'No pudimos completar la operación. Comprobá tu acceso y volvé a intentarlo.';
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
