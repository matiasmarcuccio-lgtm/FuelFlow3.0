import React from 'react';
import { useParams } from 'react-router-dom';
import { DashboardPresenter } from './DashboardPresenter';
import { useTacticalFleetMap } from './useTacticalFleetMap';

export function DashboardContainer() {
  const { projectId } = useParams<{ projectId: string }>();
  
  // Si no hay proyecto en la URL, usamos el ID por defecto de Hobart para la demo
  const targetProject = projectId || '11111111-1111-1111-1111-111111111111';

  // El modelo de lectura espacial puro (Sin estado de red, sin WebSockets aquí)
  const { fleet, hrcwPolygon } = useTacticalFleetMap(targetProject);

  return (
    <DashboardPresenter 
      fleet={fleet}
      hrcwPolygon={hrcwPolygon}
    />
  );
}
