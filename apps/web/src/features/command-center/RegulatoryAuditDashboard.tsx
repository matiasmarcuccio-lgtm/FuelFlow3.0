import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';

type AuditReportType = 'ATO_FUEL_REBATE' | 'WHS_FATIGUE_AUDIT' | 'PREDICTIVE_MAINTENANCE';

interface AuditPayload {
  success: boolean;
  report_type: AuditReportType;
  fleet_id: string;
  generated_at: string;
  data: any[];
}

export const RegulatoryAuditDashboard: React.FC = () => {
  const [activeTab, setActiveTab] = useState<AuditReportType>('ATO_FUEL_REBATE');
  const [isExporting, setIsExporting] = useState<boolean>(false);
  const [exportingLoto, setExportingLoto] = useState(false);

  const handleExportLotoCSV = async () => {
    setExportingLoto(true);
    try {
      const { data, error } = await supabase.rpc('fn_export_regulatory_report', { p_report_type: 'WHS_BREAK_GLASS_AUDIT' });
      if (error) throw error;
      
      const rows = data.data || [];
      if (rows.length === 0) {
        alert('No hay registros de Ruptura WHS en esta flota.');
        return;
      }
      
      const headers = ['Timestamp AEST', 'Gerente UID', 'Email', 'ID Candado', 'Vehiculo ID', 'Tecnico Victima UID', 'Motivo Declarado'];
      const csvContent = [
        headers.join(','),
        ...rows.map((r: any) => [
          `"${r.timestamp_aest}"`,
          `"${r.gerente_ejecutor_uid}"`,
          `"${r.gerente_email}"`,
          `"${r.lockout_id_afectado}"`,
          `"${r.vehiculo_id}"`,
          `"${r.tecnico_atropellado_uid}"`,
          `"${r.motivo_worksafe}"`
        ].join(','))
      ].join('\\n');
      
      const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.setAttribute('href', url);
      link.setAttribute('download', `WorkSafe_Audit_Lockout_Overrides_${new Date().toISOString().split('T')[0]}.csv`);
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      
    } catch (err: any) {
      console.error(err);
      alert(err.message || 'Error al exportar reporte forense WHS');
    } finally {
      setExportingLoto(false);
    }
  };

  // 1. EXTRACCIÓN SATELITAL DESDE LAS VISTAS MATERIALIZADAS EN CAPA 0
  const { data: reportPackage, isLoading, error } = useQuery<AuditPayload>({
    queryKey: ['regulatory_audit_report', activeTab],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('fn_export_regulatory_report', {
        p_report_type: activeTab,
      });

      if (error) throw new Error(error.message);
      return data as AuditPayload;
    },
    refetchOnWindowFocus: false,
  });

  // SIMULACIÓN DE DESCARGA FISCAL FORMATEADA FOR/EXCEL/CSV
  const executeDownload = () => {
    if (!reportPackage || !reportPackage.data.length) return;
    setIsExporting(true);

    try {
      const jsonString = JSON.stringify(reportPackage.data, null, 2);
      const blob = new Blob([jsonString], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      
      const link = document.createElement('a');
      link.href = url;
      link.download = `JITSITE_AUDIT_${activeTab}_${new Date().toISOString().slice(0, 10)}.json`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
    } finally {
      setIsExporting(false);
    }
  };

  if (isLoading) {
    return (
      <div className="bg-slate-950 border border-slate-800 p-12 rounded-3xl text-center font-mono uppercase text-slate-500 animate-pulse">
        [CONCILIANDO VISTAS MATERIALIZADAS EN CAPA 0... ESPERE ALINEACIÓN FORENSE]
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-950/40 border-2 border-red-800 p-6 rounded-3xl font-mono text-xs text-red-400 uppercase">
        ⚠️ ERROR JURISDICCIONAL O DE LECTURA: {(error as Error).message}
      </div>
    );
  }

  const rows = reportPackage?.data || [];

  return (
    <div className="bg-slate-950 border border-slate-800 rounded-3xl p-6 md:p-8 font-sans select-none shadow-2xl text-white">
      
      {/* Cabecera Jurisdiccional */}
      <header className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 border-b border-slate-800 pb-6 mb-6">
        <div>
          <div className="flex items-center gap-3">
            <span className="w-3 h-3 bg-emerald-500 rounded-full animate-ping"></span>
            <h2 className="text-2xl font-black uppercase tracking-tight">
              Libro Mayor y Auditoría • Regulatory Engine
            </h2>
          </div>
          <p className="text-xs font-mono text-slate-500 uppercase mt-1">
            ESTADO LEGAL: CONCILIADO AL SEGUNDO | JURISDICCIÓN: HOBART, TASMANIA
          </p>
        </div>

        <div className="flex flex-col md:flex-row gap-2">
          <button
            onClick={handleExportLotoCSV}
            disabled={exportingLoto}
            className="bg-purple-600 hover:bg-purple-500 disabled:opacity-30 text-white font-black px-6 py-4 rounded-xl uppercase tracking-widest text-xs shadow-xl transition-all flex items-center gap-2"
          >
            <span>{exportingLoto ? 'EXTRAYENDO...' : '🚨 CSV RUPTURAS WHS'}</span>
          </button>
          <button
            onClick={executeDownload}
            disabled={isExporting || rows.length === 0}
            className="bg-emerald-500 hover:bg-emerald-400 disabled:opacity-30 text-black font-black px-6 py-4 rounded-xl uppercase tracking-widest text-xs shadow-xl transition-all flex items-center gap-2"
          >
            <span>📥 DESCARGAR VISTA ACTUAL (JSON)</span>
          </button>
        </div>
      </header>

      {/* Botonera de Selección de Reporte */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-3 mb-8 font-mono text-xs">
        {[
          { id: 'ATO_FUEL_REBATE', label: '🛢️ Crédito Fiscal Diésel (ATO)', desc: 'Reembolso FTC por Diésel Fuera de Carretera' },
          { id: 'PREDICTIVE_MAINTENANCE', label: '⚙️ Roster de Mantenimiento', desc: 'Horómetros OEM y Horas para Servicio' },
          { id: 'WHS_FATIGUE_AUDIT', label: '🛑 Auditoría de Fatiga (WHS)', desc: 'Historial de Conducción Continua y Bloqueos' },
        ].map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id as AuditReportType)}
            className={`p-4 rounded-2xl border text-left transition-all ${
              activeTab === tab.id
                ? 'bg-blue-600/20 border-blue-500 text-white shadow-lg shadow-blue-500/10 scale-102'
                : 'bg-slate-900/60 border-slate-800 text-slate-400 hover:border-slate-700 hover:text-white'
            }`}
          >
            <span className="font-black text-sm block mb-1 text-white">{tab.label}</span>
            <span className="text-[10px] text-slate-400 block">{tab.desc}</span>
          </button>
        ))}
      </div>

      {/* TABLA DE EXPORTACIÓN FORENSE (HIGIENE DE CELDAS ESTRICTA) */}
      <div className="overflow-x-auto bg-slate-900/50 border border-slate-800/80 rounded-2xl">
        <table className="w-full text-left border-collapse font-mono text-xs">
          
          {/* VISTA 1: CRÉDITO FISCAL ATO */}
          {activeTab === 'ATO_FUEL_REBATE' && (
            <>
              <thead>
                <tr className="border-b border-slate-800 text-slate-400 uppercase tracking-widest text-[10px] bg-slate-900">
                  <th className="py-3 px-4">Maquinaria (ID)</th>
                  <th className="py-3 px-4">Litros Inyectados</th>
                  <th className="py-3 px-4">Gasto Total (AUD)</th>
                  <th className="py-3 px-4 text-emerald-400">Reembolso ATO Estimado</th>
                  <th className="py-3 px-4">Consumo Medio</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800/60">
                {rows.map((row: any) => (
                  <tr key={row.asset_id} className="hover:bg-slate-800/40">
                    <td className="py-3 px-4 font-bold text-white">{row.asset_name}</td>
                    <td className="py-3 px-4">{row.total_liters_injected} L</td>
                    <td className="py-3 px-4">${row.total_aud_spent}</td>
                    <td className="py-3 px-4 font-black text-emerald-400">${row.estimated_ato_rebate_aud} AUD</td>
                    <td className="py-3 px-4 text-blue-400">{row.avg_burn_rate_lph} L/h</td>
                  </tr>
                ))}
              </tbody>
            </>
          )}

          {/* VISTA 2: ROSTER DE MANTENIMIENTO PREDICTIVO */}
          {activeTab === 'PREDICTIVE_MAINTENANCE' && (
            <>
              <thead>
                <tr className="border-b border-slate-800 text-slate-400 uppercase tracking-widest text-[10px] bg-slate-900">
                  <th className="py-3 px-4">Maquinaria</th>
                  <th className="py-3 px-4">Estado WHS</th>
                  <th className="py-3 px-4">Horómetro Actual</th>
                  <th className="py-3 px-4">Horas Para Servicio</th>
                  <th className="py-3 px-4 text-right">Prioridad Técnica</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800/60">
                {rows.map((row: any) => (
                  <tr key={row.asset_id} className="hover:bg-slate-800/40">
                    <td className="py-3 px-4 font-bold text-white">{row.asset_name}</td>
                    <td className="py-3 px-4">{row.current_whs_status}</td>
                    <td className="py-3 px-4 font-bold">{row.current_engine_hours} h</td>
                    <td className="py-3 px-4">{row.hours_until_next_service} h</td>
                    <td className="py-3 px-4 text-right">
                      <span className={`px-2 py-1 rounded text-[10px] font-black ${
                        row.maintenance_priority === 'URGENT_SERVICE_DUE' 
                          ? 'bg-red-500/20 text-red-400 border border-red-500' 
                          : row.maintenance_priority === 'SERVICE_WARNING'
                          ? 'bg-amber-500/20 text-amber-400 border border-amber-500'
                          : 'bg-emerald-500/20 text-emerald-400'
                      }`}>
                        {row.maintenance_priority}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </>
          )}

          {/* VISTA 3: AUDITORÍA DE FATIGA WHS */}
          {activeTab === 'WHS_FATIGUE_AUDIT' && (
            <>
              <thead>
                <tr className="border-b border-slate-800 text-slate-400 uppercase tracking-widest text-[10px] bg-slate-900">
                  <th className="py-3 px-4">Operario WHS</th>
                  <th className="py-3 px-4">Turnos Totales</th>
                  <th className="py-3 px-4">Horas Acumuladas</th>
                  <th className="py-3 px-4">Media Conducción Continua</th>
                  <th className="py-3 px-4 text-right">Infracciones de Fatiga</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800/60">
                {rows.map((row: any) => (
                  <tr key={row.operator_uid} className="hover:bg-slate-800/40">
                    <td className="py-3 px-4 font-bold text-white">{row.operator_name}</td>
                    <td className="py-3 px-4">{row.total_shifts_worked}</td>
                    <td className="py-3 px-4">{row.total_work_hours} h</td>
                    <td className="py-3 px-4 text-blue-400">{row.avg_continuous_drive_hours} h</td>
                    <td className="py-3 px-4 text-right">
                      <span className={`px-2 py-1 rounded text-[10px] font-black ${
                        row.fatigue_lockouts_triggered > 0 
                          ? 'bg-red-600 text-white animate-pulse' 
                          : 'bg-slate-800 text-slate-400'
                      }`}>
                        {row.fatigue_lockouts_triggered} BLOQUEOS
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </>
          )}

          {rows.length === 0 && (
            <tbody>
              <tr>
                <td colSpan={5} className="py-12 text-center text-slate-600 uppercase font-mono">
                  No hay registros consolidados para este filtro en el libro mayor.
                </td>
              </tr>
            </tbody>
          )}
        </table>
      </div>

      {/* Pie de Página Forense */}
      <footer className="mt-6 pt-4 border-t border-slate-900 flex justify-between items-center font-mono text-[10px] text-slate-600 uppercase">
        <span>Sello de Custodia: REF-{reportPackage?.generated_at.slice(0, 19)}</span>
        <span>WorkSafe Tasmania • Australian Taxation Office Compliant</span>
      </footer>
    </div>
  );
};
