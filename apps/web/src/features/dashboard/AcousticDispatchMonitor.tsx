import { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { motion, AnimatePresence } from 'framer-motion';
import { RadioTower } from 'lucide-react';
import { toast, Toaster } from 'sonner';

interface AcousticDispatchMonitorProps {
    projectId: string;
}

export const AcousticDispatchMonitor: React.FC<AcousticDispatchMonitorProps> = ({ projectId }) => {
    const [dispatchEvent, setDispatchEvent] = useState<{ id: string, assetId: string, timestamp: number } | null>(null);

    useEffect(() => {
        const channel = supabase.channel(`public:jit_active_queues:dispatched:${projectId}`)
            .on('postgres_changes', { 
                event: 'UPDATE', 
                schema: 'public', 
                table: 'jit_active_queues',
                filter: `project_id=eq.${projectId}`
            }, (payload) => {
                if (payload.new.status === 'dispatched') {
                    // Trigger Sonar and Toast
                    setDispatchEvent({
                        id: payload.new.id,
                        assetId: payload.new.asset_id,
                        timestamp: Date.now()
                    });
                    
                    toast.success('Despacho Acústico Emitido', {
                        description: `Vehicle ID: ${payload.new.asset_id.substring(0, 8)}`,
                        icon: <RadioTower className="text-emerald-500 animate-pulse" />,
                        duration: 5000,
                    });
                }
            })
            .subscribe();

        return () => {
            supabase.removeChannel(channel);
        };
    }, [projectId]);

    return (
        <>
            {/* Global Toaster for Acoustic Events */}
            <Toaster theme="dark" position="top-center" />
            
            {/* Visual Sonar Overlay */}
            <div className="absolute inset-0 pointer-events-none flex items-center justify-center z-50 overflow-hidden">
                <AnimatePresence>
                    {dispatchEvent && (
                        <motion.div
                            key={dispatchEvent.timestamp}
                            initial={{ scale: 0.8, opacity: 1 }}
                            animate={{ scale: 4, opacity: 0 }}
                            exit={{ opacity: 0 }}
                            transition={{ duration: 1.5, ease: "easeOut" }}
                            className="absolute rounded-full border-4 border-emerald-500/50 bg-emerald-500/10 shadow-[0_0_100px_30px_rgba(16,185,129,0.3)]"
                            style={{ width: '300px', height: '300px' }}
                            onAnimationComplete={() => setDispatchEvent(null)}
                        >
                            <div className="absolute inset-0 flex items-center justify-center">
                                <RadioTower size={48} className="text-emerald-400 opacity-50" />
                            </div>
                        </motion.div>
                    )}
                </AnimatePresence>
            </div>
        </>
    );
};
