import { useEffect, useRef } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { supabase } from '../lib/supabase';
import type { Asset } from '../schemas/core';

export function useRealtimeSync() {
  const queryClient = useQueryClient();
  const bufferRef = useRef<{ assets: Record<string, Asset>, invalidateProjects: boolean }>({
    assets: {},
    invalidateProjects: false
  });
  const intervalRef = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    // Función central de drenaje de la Cámara de Amortiguación
    const flushBuffer = () => {
      const { assets, invalidateProjects } = bufferRef.current;
      const assetUpdates = Object.values(assets);
      
      if (assetUpdates.length > 0) {
        // 1. Agrupar actualizaciones masivas por proyecto
        const projectUpdates: Record<string, Asset[]> = {};
        assetUpdates.forEach(asset => {
            if (asset.current_project_id) {
                if (!projectUpdates[asset.current_project_id]) projectUpdates[asset.current_project_id] = [];
                projectUpdates[asset.current_project_id].push(asset);
            }
        });

        // 2. Aplicar actualizaciones en bloque al estado local (O(N) sobre el buffer, 1 render por QueryKey)
        Object.entries(projectUpdates).forEach(([projectId, newAssets]) => {
            queryClient.setQueryData(['assets', projectId], (oldData: Asset[] | undefined) => {
                if (!oldData) return oldData;
                const newMap = new Map(newAssets.map(a => [a.id, a]));
                return oldData.map(asset => newMap.has(asset.id) ? { ...asset, ...newMap.get(asset.id) } : asset);
            });
        });

        queryClient.setQueryData(['assets', 'all'], (oldData: Asset[] | undefined) => {
            if (!oldData) return oldData;
            const newMap = new Map(assetUpdates.map(a => [a.id, a]));
            return oldData.map(asset => newMap.has(asset.id) ? { ...asset, ...newMap.get(asset.id) } : asset);
        });
      }

      if (invalidateProjects) {
        // 3. Invalidación pesada (OLAP / Métricas de Negocio) agrupada en una sola llamada
        queryClient.invalidateQueries({ queryKey: ['business_metrics'] });
        queryClient.invalidateQueries({ queryKey: ['projects'] });
      }

      // Reiniciar buffer (Intervalo fijo se mantiene vivo)
      bufferRef.current = { assets: {}, invalidateProjects: false };
    };

    // Válvula de Estrangulamiento de Intervalo Fijo (Throttle)
    // Garantiza que la UI se renderice innegociablemente cada 3 segundos, previniendo inanición visual (starvation)
    intervalRef.current = setInterval(flushBuffer, 3000);

    // Escudo Zero-Trust: Sincronización Quirúrgica contra Estampidas
    const channel = supabase
      .channel('jit-field-changes')
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'assets' }, (payload) => {
        const newAsset = payload.new as Asset;
        bufferRef.current.assets[newAsset.id] = newAsset;
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'projects' }, () => {
        bufferRef.current.invalidateProjects = true;
      })
      .on('postgres_changes', { event: 'DELETE', schema: 'public', table: 'projects' }, () => {
        bufferRef.current.invalidateProjects = true;
      })
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [queryClient]);
}
