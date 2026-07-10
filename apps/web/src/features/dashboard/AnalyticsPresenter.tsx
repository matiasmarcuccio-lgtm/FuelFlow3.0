import React, { useMemo } from 'react';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, LineChart, Line, Legend } from 'recharts';

interface AnalyticsPresenterProps {
    efficiency: any[];
    production: any[];
    downtime: any[];
}

export function AnalyticsPresenter({ efficiency, production, downtime }: AnalyticsPresenterProps) {
    // Calcular KPIs para las tarjetas superiores
    const totalTonnage = production.reduce((acc, curr) => acc + (curr.total_net_weight || 0), 0);
    
    // Promedio de eficiencia ponderado por total de ciclos del día
    const totalCycles = efficiency.reduce((acc, curr) => acc + (curr.total_cycles || 0), 0);
    const avgEfficiency = totalCycles > 0 
        ? efficiency.reduce((acc, curr) => acc + ((curr.avg_loading_minutes || 0) * (curr.total_cycles || 0)), 0) / totalCycles 
        : 0;
    
    const totalDowntime = downtime.reduce((acc, curr) => acc + (curr.total_downtime_hours || 0), 0);

    // Preparar datos para Recharts
    
    // 1. Producción apilada por fecha y bloque geológico
    const productionByDate = useMemo(() => {
        const dataMap: Record<string, any> = {};
        const blocks = new Set<string>();

        production.forEach(row => {
            const d = row.date;
            const block = row.geological_block || 'UNKNOWN';
            blocks.add(block);
            if (!dataMap[d]) dataMap[d] = { date: d };
            if (!dataMap[d][block]) dataMap[d][block] = 0;
            dataMap[d][block] += row.total_net_weight;
        });

        // Convertir a array ordenado por fecha
        const dataArr = Object.values(dataMap).sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());
        return { data: dataArr, blocks: Array.from(blocks) };
    }, [production]);

    // 2. Eficiencia por fecha
    const efficiencyByDate = useMemo(() => {
        const dataMap: Record<string, { date: string, sumMinutes: number, count: number }> = {};
        
        efficiency.forEach(row => {
            const d = row.date;
            if (!dataMap[d]) dataMap[d] = { date: d, sumMinutes: 0, count: 0 };
            dataMap[d].sumMinutes += (row.avg_loading_minutes * row.total_cycles);
            dataMap[d].count += row.total_cycles;
        });

        return Object.values(dataMap)
            .map(item => ({ date: item.date, avg_minutes: item.count > 0 ? (item.sumMinutes / item.count) : 0 }))
            .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());
    }, [efficiency]);

    // Colores corporativos (Paleta de obra)
    const blockColors = ['#f59e0b', '#3b82f6', '#10b981', '#ef4444', '#8b5cf6'];

    return (
        <div className="min-h-screen bg-[#0a0a0a] text-foreground p-8">
            <header className="mb-8 border-b border-outline-variant pb-4">
                <h1 className="text-3xl font-bold text-foreground tracking-tight">Sala de Inteligencia Financiera</h1>
                <p className="text-on-surface-variant mt-1">Análisis OLAP de Rendimiento Logístico</p>
            </header>

            {/* Top Row: Header Cards */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
                <div className="bg-background border border-outline-variant p-6 rounded-xl shadow-lg">
                    <h3 className="text-sm font-medium text-on-surface-variant uppercase tracking-wide">Tonelaje Total (Semana)</h3>
                    <p className="text-4xl font-bold text-foreground mt-2">{totalTonnage.toLocaleString(undefined, { maximumFractionDigits: 1 })} T</p>
                </div>
                
                <div className={`bg-background border ${avgEfficiency > 3.0 ? 'border-red-500/50' : 'border-outline-variant'} p-6 rounded-xl shadow-lg relative overflow-hidden`}>
                    <h3 className="text-sm font-medium text-on-surface-variant uppercase tracking-wide">Eficiencia JIT (Avg)</h3>
                    <p className={`text-4xl font-bold mt-2 ${avgEfficiency > 3.0 ? 'text-red-400' : 'text-emerald-400'}`}>
                        {avgEfficiency.toFixed(2)} min/ciclo
                    </p>
                    {avgEfficiency > 3.0 && (
                        <div className="absolute top-0 right-0 w-2 h-full bg-red-500 shadow-[0_0_15px_rgba(239,68,68,0.5)]"></div>
                    )}
                </div>

                <div className="bg-background border border-outline-variant p-6 rounded-xl shadow-lg">
                    <h3 className="text-sm font-medium text-on-surface-variant uppercase tracking-wide">Impacto Fitter (Downtime)</h3>
                    <p className="text-4xl font-bold text-foreground mt-2">{totalDowntime.toFixed(1)} Hrs</p>
                </div>
            </div>

            {/* Main Body: Gráficos */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
                {/* Gráfico de Producción */}
                <div className="bg-background border border-outline-variant p-6 rounded-xl shadow-lg">
                    <h3 className="text-lg font-semibold text-foreground mb-6">Volumen de Extracción por Bloque Geológico</h3>
                    <div className="h-80 w-full">
                        <ResponsiveContainer width="100%" height="100%">
                            <AreaChart data={productionByDate.data} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
                                <defs>
                                    {productionByDate.blocks.map((block, i) => (
                                        <linearGradient key={`color-${block}`} id={`color-${block}`} x1="0" y1="0" x2="0" y2="1">
                                            <stop offset="5%" stopColor={blockColors[i % blockColors.length]} stopOpacity={0.8}/>
                                            <stop offset="95%" stopColor={blockColors[i % blockColors.length]} stopOpacity={0}/>
                                        </linearGradient>
                                    ))}
                                </defs>
                                <CartesianGrid strokeDasharray="3 3" stroke="#1e293b" vertical={false} />
                                <XAxis dataKey="date" stroke="#64748b" tickFormatter={(val) => val.substring(5)} />
                                <YAxis stroke="#64748b" />
                                <Tooltip 
                                    contentStyle={{ backgroundColor: '#0f172a', borderColor: '#334155', color: '#f8fafc' }}
                                    itemStyle={{ color: '#f8fafc' }}
                                />
                                <Legend />
                                {productionByDate.blocks.map((block, i) => (
                                    <Area 
                                        key={block} 
                                        type="monotone" 
                                        dataKey={block} 
                                        stackId="1" 
                                        stroke={blockColors[i % blockColors.length]} 
                                        fillOpacity={1} 
                                        fill={`url(#color-${block})`} 
                                    />
                                ))}
                            </AreaChart>
                        </ResponsiveContainer>
                    </div>
                </div>

                {/* Gráfico de Eficiencia */}
                <div className="bg-background border border-outline-variant p-6 rounded-xl shadow-lg">
                    <h3 className="text-lg font-semibold text-foreground mb-6">Tendencia de Eficiencia JIT</h3>
                    <div className="h-80 w-full">
                        <ResponsiveContainer width="100%" height="100%">
                            <LineChart data={efficiencyByDate} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
                                <CartesianGrid strokeDasharray="3 3" stroke="#1e293b" vertical={false} />
                                <XAxis dataKey="date" stroke="#64748b" tickFormatter={(val) => val.substring(5)} />
                                <YAxis stroke="#64748b" />
                                <Tooltip 
                                    contentStyle={{ backgroundColor: '#0f172a', borderColor: '#334155', color: '#f8fafc' }}
                                />
                                <Legend />
                                <Line 
                                    type="monotone" 
                                    dataKey="avg_minutes" 
                                    name="Promedio Min/Ciclo" 
                                    stroke="#10b981" 
                                    strokeWidth={3}
                                    dot={{ r: 4, fill: '#10b981', strokeWidth: 2 }}
                                    activeDot={{ r: 8 }}
                                />
                            </LineChart>
                        </ResponsiveContainer>
                    </div>
                </div>
            </div>
        </div>
    );
}
