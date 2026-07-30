import React, { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import type { BillingProjectSite } from '../../types/whs.types';

export const BillingPortal: React.FC<{ userEmail: string }> = ({ userEmail }) => {
  const [loading, setLoading] = useState<boolean>(false);
  const [projects, setProjects] = useState<BillingProjectSite[]>([]);
  const [activeAssetDays, setActiveAssetDays] = useState<number>(0);
  const [error, setError] = useState<string | null>(null);

  const fetchBillingOverview = async () => {
    try {
      // 1. Obtener proyectos activos y su estado de bóveda
      const { data: sitesData, error: sitesError } = await supabase
        .from('project_sites')
        .select('id, name, status, vault_status, purge_scheduled_for');
      
      if (sitesError) throw sitesError;
      setProjects(sitesData || []);

      // 2. Obtener la fotografía metrada del último ciclo (AEST)
      const { data: ledgerData, error: ledgerError } = await supabase
        .from('fleet_billing_ledger')
        .select('active_asset_count')
        .order('billing_date', { ascending: false })
        .limit(1);

      if (!ledgerError && ledgerData && ledgerData.length > 0) {
        setActiveAssetDays(ledgerData[0].active_asset_count);
      }
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Error cargando métricas de facturación';
      setError(errorMessage);
    }
  };

  useEffect(() => {
    fetchBillingOverview();
  }, []);

  const handleOpenStripePortal = async () => {
    setLoading(true);
    setError(null);
    try {
      const sessionData = await supabase.auth.getSession();
      const token = sessionData.data.session?.access_token;
      
      if (!token) {
        throw new Error('Su sesión de administrador ha expirado. Por favor, cierre sesión y vuelva a entrar.');
      }

      const response = await fetch(
        `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/create-portal-session`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ returnUrl: window.location.href }),
        }
      );

      if (!response.ok) {
        const errorBody = await response.json().catch(() => ({}));
        throw new Error(errorBody.error || `Error HTTP ${response.status}: El servidor bancario rechazó la petición.`);
      }

      const responseData = await response.json();
      const url = responseData.url;

      if (url) {
        window.location.href = url;
      } else {
        throw new Error('La respuesta del servidor no incluyó una URL válida.');
      }
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Error desconocido';
      setError('No se pudo conectar con el servidor bancario: ' + errorMessage);
      setLoading(false);
    }
  };

  const hasDelinquentVault = projects.some(p => p.vault_status === 'VAULT_DELINQUENT' || p.vault_status === 'PURGE_SCHEDULED');

  return (
    <div className="max-w-4xl w-full mx-auto bg-slate-900 border border-slate-800 rounded-xl p-8 shadow-2xl text-slate-100">
      <div className="flex items-center justify-between border-b border-slate-800 pb-6 mb-8">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-white flex items-center gap-2">
            <span>💳</span> Centro de Facturación Metrada B2B
          </h1>
          <p className="text-slate-400 mt-2 font-mono text-sm max-w-2xl">
          Dueño de Cuenta Registrado: <span className="text-blue-400">{userEmail}</span>
        </p>

        {/* BOTÓN TÁCTICO DE INYECCIÓN (BORRAR DESPUÉS) */}
        <button
          onClick={async (e) => {
            e.preventDefault();
            try {
              // 1. Verificar tu sesión activa como Dueño
              const { data: profile, error: profileErr } = await supabase.from('profiles').select('fleet_id').single();
              if (profileErr || !profile?.fleet_id) throw new Error('Debes iniciar sesión como Dueño primero.');
              
              const targetFleet = profile.fleet_id;
              const testUsers = [
                { email: 'gerente@tasmaniagravel.com.au', role: 'fleet_manager', name: 'Gerente Pruebas' },
                { email: 'despacho@tasmaniagravel.com.au', role: 'dispatcher', name: 'Control Despacho' },
                { email: 'chofer1@tasmaniagravel.com.au', role: 'driver', name: 'Chofer Uno' }
              ];

              for (const u of testUsers) {
                const { error } = await supabase.auth.signUp({
                  email: u.email,
                  password: 'TestPassword123!',
                  options: {
                    data: {
                      invited_fleet_id: targetFleet,
                      invited_role: u.role,
                      full_name: u.name
                    }
                  }
                });
                if (error) console.error(`Fallo con ${u.role}:`, error.message);
              }
              alert('Tropa inyectada con éxito en la Capa 0. Revisa Supabase.');
            } catch (err: any) {
              alert('Error: ' + err.message);
            }
          }}
          className="w-full mt-6 p-4 bg-red-900 border border-red-500 text-red-100 font-bold rounded-lg shadow-xl uppercase tracking-wider transition-colors hover:bg-red-800"
        >
          ⚠️ Inyectar Personal de Prueba (Borrar Después)
        </button>
      </div>
        <button 
          onClick={handleOpenStripePortal}
          disabled={loading}
          className="px-6 py-3 bg-emerald-600 hover:bg-emerald-500 disabled:bg-slate-700 text-white font-semibold rounded-lg shadow-lg transition-all flex items-center gap-2 text-sm"
        >
          {loading ? 'Conectando con Stripe...' : '🛡️ Administrar Tarjetas y Facturas'}
        </button>
      </div>

      {error && (
        <div className="p-4 mb-6 bg-rose-950/50 border border-rose-800 rounded-lg text-rose-300 text-sm">
          ⚠️ {error}
        </div>
      )}

      {hasDelinquentVault && (
        <div className="p-4 mb-6 bg-amber-950/80 border border-amber-600 rounded-lg text-amber-200 text-sm flex items-start gap-3">
          <span className="text-xl">⚠️</span>
          <div>
            <strong className="font-bold block">ALERTA LEGAL: Fallo de Cobro en Bóveda Pasiva ($29 AUD)</strong>
            Uno o más proyectos archivados presentan impago en Stripe. Las descargas de bitácoras oficiales (ATO/WHS) están bloqueadas. Actualice su tarjeta antes de que inicie el contador de purga legal de 90 días.
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
        <div className="p-6 bg-slate-950/60 border border-slate-800 rounded-xl">
          <div className="text-xs font-mono text-slate-400 uppercase tracking-wider mb-2">Consumo Volumétrico Hoy (AEST)</div>
          <div className="text-4xl font-extrabold text-white mb-1">{activeAssetDays}</div>
          <p className="text-xs text-slate-400">Activos físicos operando o con candado LOTO activo hoy. Días sin actividad no generan cobro metrado.</p>
        </div>

        <div className="p-6 bg-slate-950/60 border border-slate-800 rounded-xl">
          <div className="text-xs font-mono text-slate-400 uppercase tracking-wider mb-2">Estado de Bóveda Fiscal (ATO/NHVR)</div>
          <div className="text-2xl font-bold text-emerald-400 flex items-center gap-2 mb-1">
            <span className="w-3 h-3 rounded-full bg-emerald-400 animate-pulse"></span>
            RETENCIÓN 5 AÑOS ACTIVA
          </div>
          <p className="text-xs text-slate-400">Cumplimiento inmutable de Cadena de Custodia bajo sección 382 de la Ley Tributaria Australiana.</p>
        </div>
      </div>

      <h2 className="text-lg font-semibold text-white mb-4">Estado de Obras y Proyectos</h2>
      <div className="space-y-3">
        {projects.map((site) => (
          <div key={site.id} className="p-4 bg-slate-950/40 border border-slate-800/80 rounded-lg flex items-center justify-between">
            <div>
              <div className="font-medium text-white">{site.name}</div>
              <div className="text-xs font-mono text-slate-500">ID: {site.id}</div>
            </div>
            <div className="flex items-center gap-3">
              <span className={`px-2.5 py-1 rounded text-xs font-semibold ${
                site.status === 'ACTIVE' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' : 'bg-slate-800 text-slate-400'
              }`}>
                {site.status === 'ACTIVE' ? 'OBRA ACTIVA (Metrado)' : 'CLAUSURADA ($29/mes)'}
              </span>
              <span className={`px-2.5 py-1 rounded text-xs font-mono ${
                site.vault_status === 'OPERATIONAL' ? 'text-slate-400' : 'bg-rose-500/10 text-rose-400 border border-rose-500/20'
              }`}>
                {site.vault_status}
              </span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};
