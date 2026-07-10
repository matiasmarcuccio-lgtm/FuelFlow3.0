import React from 'react';
import { useParams } from 'react-router-dom';
import { WeighbridgeContainer } from '../features/weighbridge/WeighbridgeContainer';

export function WeighbridgeDashboard() {
    const { projectId } = useParams<{ projectId: string }>();
    const targetProject = projectId || 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

    return (
        <div className="h-full w-full relative overflow-hidden bg-slate-950 text-foreground">
            <WeighbridgeContainer projectId={targetProject} />
        </div>
    );
}
