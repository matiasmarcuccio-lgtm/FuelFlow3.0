import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App';
import { AuthProvider } from './context/AuthContext.tsx';
import { Toaster } from '@/components/ui/toaster';
import { ThemeProvider } from '@/components/theme-provider';
import './index.css';

import { QueryClientProvider } from '@tanstack/react-query';
import { queryClient } from './lib/queryClient';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <ThemeProvider defaultTheme="dark" storageKey="fuelflow-theme">
        <AuthProvider>
          <App />
          <Toaster />
        </AuthProvider>
      </ThemeProvider>
    </QueryClientProvider>
  </StrictMode>,
);
