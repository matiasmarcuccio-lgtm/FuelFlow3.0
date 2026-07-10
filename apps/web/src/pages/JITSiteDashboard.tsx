import React from 'react';
import { useParams } from 'react-router-dom';
import { DashboardTacticalMap } from '../features/dashboard/DashboardTacticalMap';
import { JITQueueSidebar } from '../features/dashboard/JITQueueSidebar';
import { AcousticDispatchMonitor } from '../features/dashboard/AcousticDispatchMonitor';

export function JITSiteDashboard() {
  const { projectId } = useParams<{ projectId: string }>();
  // Si no hay proyecto en la URL, usamos el ID por defecto de Hobart
  const targetProject = projectId || 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  return (
    <div className="h-full w-full relative overflow-hidden bg-gray-950 text-gray-100 flex">
      {/* Sistema de Alerta Acústica (CoR) */}
      <AcousticDispatchMonitor projectId={targetProject} />
      {/* 
        Bucle Táctico (High-Frequency Map) 
        - Z-Index 0: Actúa como fondo interactivo.
      */}
      <div className="absolute inset-0 z-0">
        <DashboardTacticalMap projectId={targetProject} />
      </div>

      {/* 
        Bucle de Interfaz (Low-Frequency React DOM) 
        - Z-Index 10: Panel flotante o lateral para la gestión JIT.
      */}
      <div className="relative z-10 h-full flex justify-end w-full pointer-events-none">
        {/* Pointer-events-auto permite hacer click en la sidebar sin bloquear el mapa */}
        <div className="pointer-events-auto h-full">
            <JITQueueSidebar projectId={targetProject} />
        </div>
      </div>
    </div>
  );
}
