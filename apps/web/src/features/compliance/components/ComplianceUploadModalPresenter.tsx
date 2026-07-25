import React, { useState } from 'react';
import { AlertCircle, FileText, X } from 'lucide-react';

interface ComplianceUploadModalPresenterProps {
  driverName: string;
  isUploading: boolean;
  isRetrying: boolean;
  networkError: string | null;
  onCancel: () => void;
  onSubmit: (file: File, expiryDate: string) => void;
}

export const ComplianceUploadModalPresenter: React.FC<ComplianceUploadModalPresenterProps> = ({ 
  driverName, 
  isUploading,
  isRetrying,
  networkError, 
  onCancel, 
  onSubmit 
}) => {
  const [file, setFile] = useState<File | null>(null);
  const [expiryDate, setExpiryDate] = useState<string>('');
  const [localError, setLocalError] = useState<string | null>(null);

  const handleSubmit = () => {
    setLocalError(null);
    if (!file) {
      setLocalError('Por favor, selecciona un documento PDF o JPG.');
      return;
    }
    if (!expiryDate) {
      setLocalError('Por favor, indica la fecha de expiración de la póliza.');
      return;
    }
    onSubmit(file, expiryDate);
  };

  const displayError = localError || networkError;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-white rounded-lg shadow-xl w-full max-w-md overflow-hidden flex flex-col max-h-full">
        <div className="p-4 border-b bg-red-50 flex justify-between items-center">
          <div className="flex items-center space-x-2 text-red-700">
            <AlertCircle size={20} />
            <h3 className="font-bold text-lg">Regularización WHS</h3>
          </div>
          <button onClick={onCancel} className="text-gray-500 hover:text-gray-700" disabled={isUploading}>
            <X size={20} />
          </button>
        </div>

        <div className="p-6 overflow-y-auto">
          <p className="text-sm text-gray-600 mb-6">
            La póliza de seguro de <strong>{driverName}</strong> está vencida. Suba un documento válido para generar un sello forense inmutable (CoR).
          </p>

          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Póliza (PDF/JPG)</label>
              <div className="border-2 border-dashed border-gray-300 rounded-lg p-4 text-center hover:bg-gray-50 cursor-pointer relative">
                <input 
                  type="file" 
                  accept=".pdf, .jpg, .jpeg, .png"
                  className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                  onChange={(e) => setFile(e.target.files?.[0] || null)}
                  disabled={isUploading}
                />
                <div className="flex flex-col items-center justify-center space-y-2">
                  <FileText className={file ? "text-green-500" : "text-gray-400"} size={32} />
                  <span className="text-sm font-medium text-gray-700">
                    {file ? file.name : "Haga clic o arrastre el archivo aquí"}
                  </span>
                </div>
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Nueva Fecha de Expiración</label>
              <input 
                type="date" 
                className="w-full border border-gray-300 rounded-md p-2 focus:ring-red-500 focus:border-red-500"
                value={expiryDate}
                onChange={(e) => setExpiryDate(e.target.value)}
                disabled={isUploading}
                min={new Date().toISOString().split('T')[0]}
              />
            </div>

            {displayError && (
              <div className="bg-red-50 text-red-700 p-3 rounded-md text-sm">
                {displayError}
              </div>
            )}
          </div>
        </div>

        <div className="p-4 border-t bg-gray-50 flex justify-end space-x-3">
          <button 
            className="px-4 py-2 border border-gray-300 rounded-md text-gray-700 hover:bg-gray-100 font-medium"
            onClick={onCancel}
            disabled={isUploading}
          >
            Cancelar
          </button>
          <button 
            className={`px-4 py-2 text-white rounded-md font-medium flex items-center disabled:opacity-50 ${isRetrying ? 'bg-orange-500 hover:bg-orange-600' : 'bg-red-600 hover:bg-red-700'}`}
            onClick={handleSubmit}
            disabled={isUploading}
          >
            {isRetrying ? 'Sincronizando...' : isUploading ? 'Sellando...' : 'Aplicar Sello WHS'}
          </button>
        </div>
      </div>
    </div>
  );
};
