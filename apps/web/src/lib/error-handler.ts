import { isFuelFlowError } from '@/types/errors';
import { toast } from '@/hooks/use-toast';

export const handleDatabaseError = (error: unknown, queryClient?: any) => {
  if (!isFuelFlowError(error)) {
    // Si no es un error de negocio, es un fallo crítico del sistema
    console.error("Fallo técnico no clasificado:", error);
    toast({ 
      title: "Error Operativo", 
      description: "El sistema no pudo procesar la solicitud.", 
      variant: "destructive" 
    });
    return;
  }

  // Ahora TS te obliga a manejar cada caso de DbErrorCode
  switch (error.code) {
    case 'CONTRACT_LOCKED':
      toast({ 
        title: "Contrato Bloqueado", 
        description: "Esta puja ya no admite cambios.", 
        variant: "destructive" 
      });
      break;
    case 'INSURANCE_EXPIRED':
      toast({ 
        title: "Acceso Denegado", 
        description: "Redirigiendo a cumplimiento...", 
        variant: "destructive" 
      });
      window.location.href = "/perfil/cumplimiento";
      break;
    case 'PERMISSION_DENIED':
      toast({ 
        title: "Permiso Denegado", 
        description: "No tienes la autorización necesaria para realizar esta acción.", 
        variant: "destructive" 
      });
      break;
    case 'VALIDATION_ERROR':
    default:
      toast({ 
        title: "Error de Validación", 
        description: error.message || "Los datos proporcionados no son válidos.", 
        variant: "destructive" 
      });
      break;
  }
};
