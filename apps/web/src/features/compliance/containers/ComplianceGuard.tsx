
import { useComplianceStatus } from '../hooks/useComplianceStatus';
import { ComplianceScreen } from '../components/ComplianceScreen';

const LoadingScreen = () => (
  <div className="flex h-screen w-full items-center justify-center bg-gray-50">
    <div className="text-center">
      <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-900 mx-auto mb-4"></div>
      <p className="text-gray-600 font-medium">Verificando estado de cumplimiento forense...</p>
    </div>
  </div>
);

export const ComplianceGuard = ({ children }: { children: React.ReactNode }) => {
  const { data, isLoading, isError } = useComplianceStatus();

  // El sistema bloquea todo hasta que el servidor responde (Zero-Trust UI)
  if (isLoading) return <LoadingScreen />; 
  
  if (isError || !data?.is_verified || !data?.insurance_compliant) {
    return <ComplianceScreen />; // Redirección forzada al "Bunker" de documentos
  }

  return <>{children}</>; // Acceso concedido al resto de la aplicación
};
