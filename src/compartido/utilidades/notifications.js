import { toast } from 'sonner';

export function friendlyError(error) {
  const message = error?.message || 'No se pudo completar la operación.';

  if (/Invalid login credentials|Email not confirmed/i.test(message)) {
    return 'Revisá tu correo y contraseña, o pedí ayuda al administrador.';
  }

  if (error?.code === '23505') {
    return 'Ya existe un registro con esos datos. Revisá el código y volvé a intentar.';
  }

  if (/fetch failed|Failed to fetch|NetworkError|Load failed/i.test(message)) {
    return 'Se cortó la conexión. Si la operación ya había llegado al servidor, reintentar no la repite. Revisá tu internet y comprobá el resultado antes de volver a intentar.';
  }

  if (error?.code === '57014' || /statement timeout/i.test(message)) {
    return 'El servidor tardó demasiado y canceló la operación: no se guardó nada. Probá con menos ítems por vez y avisá al administrador.';
  }

  if (/permission denied|row-level security|PGRST|function public\.|relation public\.|JWT/i.test(message)) {
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
