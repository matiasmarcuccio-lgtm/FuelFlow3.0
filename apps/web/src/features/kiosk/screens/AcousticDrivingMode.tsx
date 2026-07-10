import React from 'react';

export const AcousticDrivingMode = () => {
    return (
        <div className="w-screen h-screen bg-black flex items-center justify-center overflow-hidden pointer-events-none">
            {/* Indicador sutil de que el motor JIT acústico está vivo */}
            <div className="animate-pulse w-32 h-32 rounded-full border-4 border-emerald-900 opacity-20 flex items-center justify-center">
                <div className="w-16 h-16 rounded-full bg-emerald-900"></div>
            </div>
        </div>
    );
};
