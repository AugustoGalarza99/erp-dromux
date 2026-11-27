import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import { notifyError, notifySuccess } from '../../lib/notifications';
import { acceptInvitation } from '../../services/administration';

export default function AcceptInvite() {
  const { token } = useParams();
  const navigate = useNavigate();
  const { user, refresh } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [mode, setMode] = useState('login');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');

  useEffect(() => {
    if (!user) return;
    let mounted = true;
    setBusy(true);

    acceptInvitation(token)
      .then(async () => {
        await refresh();
        if (mounted) {
          notifySuccess('Invitación aceptada', 'Ya podés usar tu espacio de trabajo.');
          navigate('/', { replace: true });
        }
      })
      .catch((err) => {
        if (mounted) setError(notifyError(err));
      })
      .finally(() => {
        if (mounted) setBusy(false);
      });

    return () => { mounted = false; };
  }, [user?.id, token]);

  const handleAuth = async (event) => {
    event.preventDefault();
    setBusy(true);
    setError('');
    setMessage('');

    try {
      const result = mode === 'signup'
        ? await supabase.auth.signUp({ email, password })
        : await supabase.auth.signInWithPassword({ email, password });
      if (result.error) throw result.error;

      if (mode === 'signup' && !result.data.session) {
        setMessage('Revisá tu correo y confirmá tu cuenta. Después volvé a este enlace.');
        notifySuccess('Cuenta creada', 'Revisá tu correo y confirmá tu cuenta.');
      } else {
        notifySuccess('Sesión iniciada');
      }
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="setup invite-screen">
      <span className="brand-mark">D</span>
      <span className="eyebrow">INVITACIÓN AL ERP</span>
      <h1>Unite al equipo</h1>
      <p>
        Ingresá con el correo al que te invitaron. Si aún no tenés una cuenta
        en este ERP, registrate y confirmá tu correo antes de continuar.
      </p>

      {user ? (
        <div className="invite-panel">
          <p>Sesión actual: <strong>{user.email}</strong></p>
          {busy && <p>Comprobando invitación…</p>}
          {error && (
            <>
              <p role="alert" className="error">{error}</p>
              <button className="button outline" onClick={() => supabase.auth.signOut()}>
                Usar otra cuenta
              </button>
            </>
          )}
        </div>
      ) : (
        <div className="invite-panel">
          <div className="invite-tabs">
            <button className={mode === 'login' ? 'selected' : ''} onClick={() => setMode('login')}>
              Ya tengo cuenta
            </button>
            <button className={mode === 'signup' ? 'selected' : ''} onClick={() => setMode('signup')}>
              Crear cuenta
            </button>
          </div>
          <form onSubmit={handleAuth}>
            <input
              type="email"
              required
              autoComplete="email"
              placeholder="Correo invitado"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
            />
            <input
              type="password"
              required
              minLength={6}
              autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
              placeholder="Contraseña"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
            <button className="button primary" disabled={busy}>
              {busy ? 'Continuando…' : mode === 'login' ? 'Iniciar sesión' : 'Crear cuenta'}
            </button>
          </form>
          {error && <p role="alert" className="error">{error}</p>}
          {message && <p role="status" className="success">{message}</p>}
        </div>
      )}

      <Link to="/login" className="text-button">Volver al inicio de sesión</Link>
    </div>
  );
}
