import { Clock } from 'lucide-react';

interface JITQueueSidebarPresenterProps {
    queue: any[];
    isLoading: boolean;
    onDispatch: (id: string, assetLabel: string) => void;
    onNewDispatch?: () => void;
}

export const JITQueueSidebarPresenter: React.FC<JITQueueSidebarPresenterProps> = ({ queue, isLoading, onDispatch, onNewDispatch }) => {
    return (
        <aside className="h-full w-full flex flex-col pointer-events-auto bg-card">
            <div className="flex-1 flex flex-col overflow-hidden">
                
                {/* Header */}
                <div className="p-4 md:p-6 flex items-center justify-between border-b border-border">
                    <div className="flex items-center gap-2 md:gap-3">
                        <span className="material-symbols-outlined text-primary">local_shipping</span>
                        <div>
                            <h2 className="font-mono text-lg md:text-[24px] font-bold tracking-tight uppercase text-foreground">JITQueue</h2>
                            <p className="hidden md:block font-sans text-sm text-muted-foreground opacity-70">Next Dispatch Operations</p>
                        </div>
                    </div>
                    <button className="text-muted-foreground hover:text-foreground transition-colors">
                        <span className="material-symbols-outlined">more_horiz</span>
                    </button>
                </div>

                {/* Queue List */}
                <div className="flex-1 overflow-y-auto no-scrollbar p-4 md:px-6 md:pb-24 space-y-4 custom-scrollbar bg-background/50">
                    {isLoading && (
                        <div className="animate-pulse space-y-4">
                            <div className="h-24 bg-card border border-border rounded-none"></div>
                            <div className="h-24 bg-card border border-border rounded-none"></div>
                        </div>
                    )}
                    
                    {!isLoading && (!queue || queue.length === 0) && (
                        <div className="text-center p-8 text-muted-foreground font-bold border-2 border-dashed border-border rounded-none text-xs uppercase font-mono tracking-widest bg-card">
                            No Vehicles in Queue
                        </div>
                    )}

                    {!isLoading && queue?.map((item, index) => {
                        const waitTimeMs = Date.now() - new Date(item.joined_queue_at || '').getTime();
                        const waitTimeMins = Math.floor(waitTimeMs / 60000);
                        const isStagnant = waitTimeMins >= 15;
                        const assetLabel = (item.assets as any)?.registration_number || 'Truck';
                        const isFirst = index === 0;

                        return (
                            <div 
                                key={item.id} 
                                className={`bg-card border border-border rounded-none p-4 group transition-all relative overflow-hidden ${isFirst ? 'hover:border-primary/50' : ''} ${isStagnant ? 'border-destructive/50' : ''}`}
                            >
                                {isFirst && <div className="absolute top-0 left-0 w-1 h-full bg-primary shadow-[0_0_15px_rgba(34,197,94,1)]"></div>}
                                
                                <div className="flex justify-between items-start mb-4 relative z-10">
                                    <div className="flex flex-col">
                                        <span className="font-mono text-sm font-bold text-foreground">#{index + 1} {assetLabel}</span>
                                        <span className="font-mono text-[10px] text-muted-foreground uppercase mt-0.5">ID: {item.id.substring(0, 8)}</span>
                                    </div>
                                    <div className={`px-2 py-0.5 rounded-none text-[10px] font-mono font-bold tracking-wider border ${isFirst ? 'bg-primary/10 text-primary border-primary/20' : isStagnant ? 'bg-destructive/10 text-destructive border-destructive/20' : 'bg-secondary/20 text-muted-foreground border-border'}`}>
                                        {isFirst ? 'NEXT' : 'WAITING'}
                                    </div>
                                </div>

                                <div className="space-y-2 relative z-10">
                                    <div className="flex justify-between text-[10px] font-mono uppercase tracking-widest">
                                        <span className="text-muted-foreground flex items-center gap-1.5 font-bold"><Clock size={10} /> Wait Time</span>
                                        <span className={isStagnant ? 'text-destructive font-bold' : 'text-foreground font-bold'}>{waitTimeMins} mins</span>
                                    </div>
                                    <div className="w-full bg-background border border-border h-1.5 overflow-hidden">
                                        <div className={`h-full ${isStagnant ? 'bg-destructive' : 'bg-primary shadow-[0_0_8px_rgba(34,197,94,0.5)]'}`} style={{ width: `${Math.min(100, (waitTimeMins / 15) * 100)}%` }}></div>
                                    </div>
                                </div>

                                {isFirst && (
                                    <button 
                                        onClick={() => onDispatch(item.id, assetLabel)}
                                        className="w-full py-2.5 mt-4 bg-primary text-primary-foreground font-mono font-bold uppercase tracking-widest text-[10px] rounded-none flex items-center justify-center gap-1.5 hover:brightness-110 active:scale-[0.98] transition-all shadow-[0_0_15px_rgba(34,197,94,0.2)] relative z-10"
                                    >
                                        <span className="material-symbols-outlined text-[14px]">play_arrow</span> DISPATCH NOW
                                    </button>
                                )}
                            </div>
                        );
                    })}
                </div>

                {/* Footer */}
                <div className="p-4 md:p-6 bg-card/95 backdrop-blur-md border-t border-border shrink-0 mt-auto">
                    <button 
                        onClick={onNewDispatch}
                        className="w-full h-12 bg-primary hover:bg-primary/90 text-primary-foreground font-mono font-bold tracking-[0.2em] flex items-center justify-center gap-3 transition-all active:scale-[0.98] rounded-none uppercase text-[10px] shadow-[0_0_15px_rgba(34,197,94,0.15)]"
                    >
                        <span className="material-symbols-outlined">add</span>
                        <span>NEW DISPATCH</span>
                    </button>
                </div>
            </div>
        </aside>
    );
};
