import { useEffect, useState } from 'react';
import { KeyRound, UserRound } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { friendlyError, notifyError, notifySuccess } from '../../lib/notifications';
import './profile.css';

export default function ProfilePage() {
  const { user, activeCompany } = useAuth();
  const [name, setName] = useState(user?.user_metadata?.full_name ?? '');
  const [phone, setPhone] = useState(user?.user_metadata?.phone ?? '');
  const [currentPassword, setCurrentPassword] = useState('');
  const [nextPassword, setNextPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    setName(user?.user_metadata?.full_name ?? '');
    setPhone(user?.user_metadata?.phone ?? '');
  }, [user?.id]);

  async function saveProfile(event) {
    event.preventDefault();
    if (busy) return;
    setBusy('profile');
    setError('');
    try {
      const result = await supabase.auth.updateUser({
        data: {
          full_name: name.trim(),
          phone: phone.trim(),
        },
      });
      if (result.error) throw result.error;
      notifySuccess('Perfil actualizado', 'Tus datos personales se guardaron correctamente.');
    } catch (cause) {
      setError(friendlyError(cause));
      notifyError(cause);
    } finally {
      setBusy('');
    }
  }

  async function changePassword(event) {
    event.preventDefault();
    if (busy) return;
    if (nextPassword.length < 12 || nextPassword !== confirmation
      || nextPassword === currentPassword) {
      setError('La nueva contraseña debe tener al menos 12 caracteres, ser distinta de la actual y coincidir con la confirmación.');
      return;
    }
    setBusy('password');
    setError('');
    try {
      const verified = await supabase.auth.signInWithPassword({
        email: user.email,
        password: currentPassword,
      });
      if (verified.error) throw new Error('La contraseña actual no es correcta.');
      const result = await supabase.auth.updateUser({ password: nextPassword });
      if (result.error) throw result.error;
      setCurrentPassword('');
      setNextPassword('');
      setConfirmation('');
      notifySuccess('Contraseña actualizada', 'Usá tu nueva contraseña la próxima vez que ingreses.');
    } catch (cause) {
      setError(friendlyError(cause));
      notifyError(cause);
    } finally {
      setBusy('');
    }
  }

  return (
    <section className="erp-profile-page">
      <div className="page-head">
        <div>
          <span className="eyebrow">MI CUENTA</span>
          <h1>Mi perfil</h1>
          <p>Administrá tus datos y el acceso a tu cuenta.</p>
        </div>
      </div>
      <div className="erp-profile-grid">
        <form className="erp-profile-card" onSubmit={saveProfile}>
          <div className="erp-profile-title"><UserRound size={21} /><h2>Datos personales</h2></div>
          <label>Nombre completo
            <input required maxLength={100} value={name}
              onChange={(event) => setName(event.target.value)} autoComplete="name" />
          </label>
          <label>Teléfono (opcional)
            <input type="tel" maxLength={40} value={phone}
              onChange={(event) => setPhone(event.target.value)} autoComplete="tel" />
          </label>
          <label>Correo de acceso
            <input type="email" value={user?.email ?? ''} readOnly />
          </label>
          <p className="erp-profile-hint">Empresa actual: {activeCompany?.name}. El correo de acceso se gestiona por separado con el administrador.</p>
          <button className="button primary" disabled={Boolean(busy) || !name.trim()}>
            {busy === 'profile' ? 'Guardando…' : 'Guardar datos'}
          </button>
        </form>
        <form className="erp-profile-card" onSubmit={changePassword}>
          <div className="erp-profile-title"><KeyRound size={21} /><h2>Seguridad</h2></div>
          <label>Contraseña actual
            <input type="password" required value={currentPassword}
              onChange={(event) => setCurrentPassword(event.target.value)} autoComplete="current-password" />
          </label>
          <label>Contraseña nueva
            <input type="password" required minLength={12} value={nextPassword}
              onChange={(event) => setNextPassword(event.target.value)} autoComplete="new-password" />
          </label>
          <label>Confirmar contraseña nueva
            <input type="password" required minLength={12} value={confirmation}
              onChange={(event) => setConfirmation(event.target.value)} autoComplete="new-password" />
          </label>
          <p className="erp-profile-hint">Usá al menos 12 caracteres. Se verificará tu contraseña actual antes de guardar la nueva.</p>
          <button className="button primary" disabled={Boolean(busy)}>
            {busy === 'password' ? 'Actualizando…' : 'Cambiar contraseña'}
          </button>
        </form>
      </div>
      {error && <p role="alert" className="error">{error}</p>}
    </section>
  );
}
