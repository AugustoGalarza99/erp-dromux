import React from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { QueryClientProvider } from '@tanstack/react-query';
import { Toaster } from 'sonner';
import { queryClient } from './lib/queryClient';
import { configured } from './lib/supabase';
import { AuthProvider } from './contexts/AuthContext';
import App from './app/App';
import './styles.css';
import './erpPolish.css';

function MissingConfiguration() {
  return (
    <div className="setup">
      <span className="brand-mark">D</span>
      <h1>Configuración pendiente</h1>
      <p>
        Pedile al administrador que termine de configurar el acceso al sistema.
      </p>
    </div>
  );
}

createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        {configured ? (
          <AuthProvider>
            <App />
          </AuthProvider>
        ) : (
          <MissingConfiguration />
        )}
      </BrowserRouter>
      <Toaster
        position="top-right"
        richColors
        closeButton
        expand
        toastOptions={{ duration: 4000, className: 'erp-toast' }}
      />
    </QueryClientProvider>
  </React.StrictMode>,
);
