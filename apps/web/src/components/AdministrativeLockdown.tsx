import React from 'react';
import { Lock } from 'lucide-react';

export const AdministrativeLockdown: React.FC = () => {
  return (
    <div className="min-h-screen bg-black text-white p-6 md:p-12 flex flex-col justify-between font-sans select-none border-8 border-orange-600">
      <header className="flex justify-between items-center border-b-2 border-orange-800 pb-4">
        <span className="bg-orange-600 text-black font-mono font-black text-xs px-3 py-1 uppercase tracking-widest">
          BLOQUEO ADMINISTRATIVO • ENCLAVAMIENTO ACTIVO
        </span>
        <span className="font-mono text-xs text-orange-400 font-bold uppercase">TERMINAL RESTRINGIDA</span>
      </header>

      <main className="max-w-2xl mx-auto my-auto text-center py-8">
        <Lock className="w-24 h-24 text-orange-600 mx-auto mb-6" />
        <h1 className="text-3xl font-black mb-4 uppercase tracking-wider text-orange-500">
          Terminal Bloqueada
        </h1>
        <p className="text-xl text-gray-300 font-medium mb-8 leading-relaxed uppercase tracking-wide">
          El uso de este equipo ha sido suspendido temporalmente desde la Central.
        </p>
        
        <div className="bg-gray-900 border-l-4 border-orange-600 p-6 text-left max-w-lg mx-auto rounded-r-lg">
          <p className="text-gray-400 font-mono text-sm uppercase mb-2">Instrucciones para el Operador:</p>
          <p className="text-white font-medium text-lg">
            Por favor, comuníquese inmediatamente con su Supervisor o Central de Despacho e informe que su terminal se encuentra bajo suspensión administrativa.
          </p>
        </div>
      </main>

      <footer className="border-t-2 border-gray-900 pt-4 flex justify-between items-center text-gray-500 font-mono text-xs uppercase">
        <span>SISTEMA DE CONTROL FUELFLOW</span>
        <span>NO INTENTE FORZAR EL ARRANQUE</span>
      </footer>
    </div>
  );
};
