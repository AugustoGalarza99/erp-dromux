import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  // Los PDF se cargan con import() dinámico: sin esto Vite descubre jspdf al primer clic,
  // reoptimiza las dependencias en caliente y el navegador recibe 504 "Outdated Optimize Dep".
  optimizeDeps: {
    include: ['jspdf', 'jspdf-autotable'],
  },
});
