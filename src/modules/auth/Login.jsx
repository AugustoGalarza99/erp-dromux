import { useState } from 'react';
import { Navigate } from 'react-router-dom';
import { ArrowRight, LockKeyhole, Mail } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import { notifyError, notifySuccess } from '../../lib/notifications';

export default function Login() {
  const { user } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  if (user) return <Navigate to="/" replace />;

  const handleSubmit = async (event) => {
    event.preventDefault();
    setBusy(true);
    setError('');

    try {
      const result = await supabase.auth.signInWithPassword({ email, password });
      if (result.error) throw result.error;
      notifySuccess('Sesión iniciada', 'Bienvenido a tu espacio de trabajo.');
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="auth-screen">
      <aside className="auth-story">
        <div className="brand brand-light">
          <span className="brand-mark">D</span>
          <span>DROMUX <small>ERP</small></span>
        </div>

        <div>
          <span className="eyebrow light">TU ESPACIO DE TRABAJO</span>
          <h1>
            Una operación más clara.<br />
            <em>Una empresa más ágil.</em>
          </h1>
          <p>El centro de control para conectar inventario, producción y decisiones de negocio.</p>
        </div>

        <span className="story-foot">Diseñado para crecer con tu empresa.</span>
      </aside>

      <main className="auth-form-wrap">
        <div className="auth-form">
          <span className="eyebrow">BIENVENIDO DE NUEVO</span>
          <h2>Iniciá sesión</h2>
          <p>Ingresá con la cuenta de tu empresa.</p>

          <form onSubmit={handleSubmit}>
            <label>
              Correo electrónico
              <div className="input-wrap">
                <Mail size={18} />
                <input
                  type="email"
                  autoComplete="email"
                  required
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  placeholder="tu@empresa.com"
                />
              </div>
            </label>

            <label>
              Contraseña
              <div className="input-wrap">
                <LockKeyhole size={18} />
                <input
                  type="password"
                  autoComplete="current-password"
                  required
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  placeholder="Tu contraseña"
                />
              </div>
            </label>

            {error && <p role="alert" className="error">{error}</p>}

            <button className="button primary full" disabled={busy}>
              {busy ? 'Ingresando…' : 'Entrar al espacio'}
              <ArrowRight size={18} />
            </button>
          </form>

          <p className="auth-note">
            El alta de usuarios se habilitará desde administración. Para el primer
            acceso, creá tu usuario en Supabase Auth.
          </p>
        </div>
      </main>
    </div>
  );
}
