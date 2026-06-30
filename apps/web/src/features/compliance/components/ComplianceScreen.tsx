import React from 'react';

export const ComplianceScreen = () => {
  return (
    <div className="flex h-screen w-full items-center justify-center bg-red-50 p-6">
      <div className="max-w-md w-full bg-white p-8 rounded-lg shadow-xl border-t-4 border-red-600 text-center">
        <h2 className="text-2xl font-bold text-gray-900 mb-2">Acceso Denegado</h2>
        <h3 className="text-lg font-semibold text-red-600 mb-6">Bloqueo de Cumplimiento (CoR)</h3>
        
        <p className="text-gray-600 mb-6 text-sm">
          Tu póliza de seguro de carga ha expirado o tus documentos reglamentarios aún no han sido verificados por el departamento WHS.
        </p>
        
        <div className="bg-gray-50 p-4 rounded-md mb-6 border border-gray-200">
          <p className="text-xs text-gray-500 font-mono">
            Las operaciones de matchmaking y la visualización de ofertas están bloqueadas hasta que la regularización sea confirmada en la Cadena de Custodia.
          </p>
        </div>

        <button 
          className="w-full bg-red-600 hover:bg-red-700 text-white font-bold py-3 px-4 rounded transition-colors"
          onClick={() => {
            // Aquí se conectará la mutación para subir documentos usando el Edge Function upload-compliance-doc
            console.log("Abrir modal de carga de documentos");
          }}
        >
          Actualizar Póliza
        </button>
      </div>
    </div>
  );
};
