import React from 'react';
import { useParams } from 'react-router-dom';
import { AnalyticsPresenter } from './AnalyticsPresenter';
import { useManagerialKPIs } from './useManagerialKPIs';

export function AnalyticsContainer() {
    const { projectId } = useParams<{ projectId: string }>();
    const targetProject = projectId || '11111111-1111-1111-1111-111111111111';

    // 7 días de lookback por defecto
    const { data: kpis, isLoading, error } = useManagerialKPIs(targetProject, 7);

    if (isLoading) return <div className="p-8 text-foreground">Cargando Inteligencia Financiera...</div>;
    if (error) return <div className="p-8 text-red-500">Error al cargar las métricas.</div>;

    return (
        <AnalyticsPresenter 
            efficiency={kpis?.efficiency || []}
            production={kpis?.production || []}
            downtime={kpis?.downtime || []}
        />
    );
}
