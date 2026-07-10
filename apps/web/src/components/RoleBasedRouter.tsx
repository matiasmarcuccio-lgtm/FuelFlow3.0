import React from 'react';
import { Navigate } from 'react-router-dom';
import type { UserProjectRole } from '../hooks/useUserRole';
import { AppLayout } from './layout/AppLayout';
import { KinematicKiosk } from '../features/kiosk/KinematicKiosk';
import { ShieldCheck } from 'lucide-react';

import { TollgateContainer } from '../features/tollgate/TollgateContainer';

import { DiagnosticsContainer } from '../features/diagnostics/DiagnosticsContainer';

export const RoleBasedRouter = ({ activeRole }: { activeRole: UserProjectRole }) => {
    const { role, project_id } = activeRole;

    switch (role) {
        case 'supervisor':
        case 'site_manager':
        case 'lead_supervisor':
            // El supervisor accede al Command Center completo
            return <AppLayout />;
            
        case 'weighbridge':
            // El operador de báscula entra a su entorno forense aislado
            return <TollgateContainer projectId={project_id} />;
            
        case 'fitter':
        case 'heavy_mechanic':
            // El mecánico de planta entra al escáner de red tags
            return <DiagnosticsContainer projectId={project_id} />;
            
        case 'operator':
            // El maquinista va directo al escáner QR para tomar posesión de una máquina
            return <Navigate to={`/scan`} replace />;
            
        default:
            return (
                <div className="w-screen h-screen bg-background flex flex-col items-center justify-center text-on-surface">
                    <ShieldCheck className="w-16 h-16 text-red-500 mb-4" />
                    <h1 className="text-xl font-bold text-foreground mb-2">Rol No Reconocido</h1>
                    <p>El sistema no reconoce la directiva operativa '{role}'. Contacte a administración.</p>
                </div>
            );
    }
};
