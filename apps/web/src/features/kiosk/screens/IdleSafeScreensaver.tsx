

export const IdleSafeScreensaver = () => {
    return (
        <div className="w-screen h-screen bg-black flex flex-col justify-between p-8 text-neutral-500">
            <div className="flex justify-between items-start">
                <span className="font-mono text-2xl tracking-widest">JITSite // SECURE</span>
                <span className="font-mono text-xl text-emerald-700">● T-LINK ACTIVE</span>
            </div>
            
            <div className="flex flex-col items-center justify-center">
                <h1 className="text-8xl font-black text-neutral-800 tracking-tighter">STANDBY</h1>
                <p className="mt-4 text-2xl text-neutral-600 font-mono">
                    AWAITING TACTICAL GEOMETRY INTERSECTION
                </p>
            </div>
            
            <div className="flex justify-between items-end font-mono text-xl">
                <span>V_T: 0.0 M/S</span>
                <span>SYSTEM ARMED</span>
            </div>
        </div>
    );
};
