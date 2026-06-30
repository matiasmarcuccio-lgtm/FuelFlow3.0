// Mapeo exacto de los RAISE EXCEPTION que definimos en los Triggers de Postgres
export type DbErrorCode = 
  | 'CONTRACT_LOCKED' 
  | 'INSURANCE_EXPIRED' 
  | 'PERMISSION_DENIED' 
  | 'VALIDATION_ERROR';

export interface FuelFlowError extends Error {
  code: DbErrorCode;
  details?: Record<string, any>;
}

// Discriminador de tipos para asegurar que el middleware no olvide ningún caso
export const isFuelFlowError = (error: unknown): error is FuelFlowError => {
  return typeof error === 'object' && error !== null && 'code' in error;
};
