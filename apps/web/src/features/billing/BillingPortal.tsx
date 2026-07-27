import React, { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { BillingProjectSite } from '../../types/whs.types';

export const BillingPortal: React.FC<{ userEmail: string }> = ({ userEmail }) => {
  const [loading, setLoading] = useState<boolean>(false);
  const [projects, setProjects] = useState<BillingProjectSite[]>([]);
  const [activeAssetDays, setActiveAssetDays] = useState<number>(0);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchBillingOverview();
  }, []);

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
    } catch (err: any) {
      setError(err.message || 'Error cargando métricas de facturación');
    }
  };

  const handleOpenStripePortal = async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, error: fnError } = await supabase.functions.invoke('create-portal-session', {
        body: { returnUrl: window.location.href }
      });
      if (fnError) throw fnError;
      if (data?.url) {
        window.location.href = data.url; // Redirección segura a Stripe PCI-DSS
      }
    } catch (err: any) {
      setError('No se pudo conectar con el servidor bancario: ' + err.message);
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
          <p className="text-slate-400 text-sm mt-1">Dueño de Cuenta Registrado: <span className="font-mono text-emerald-400">{userEmail}</span></p>
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
