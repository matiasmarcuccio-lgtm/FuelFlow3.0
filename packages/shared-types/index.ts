import type { Database } from './database.types';

export const ASSET_TYPES = [
  'Light Commercial',
  'Light Rigid (LR)',
  'Medium Rigid (MR)',
  'Heavy Rigid (HR)',
  'Prime Mover (HC)',
  'Prime Mover (MC)',
  'Standalone Trailer'
] as const;

export const TRAILER_TYPES = [
  'Tautliner',
  'Flatbed',
  'Drop Deck',
  'Refrigerated',
  'Skeleton',
  'Tipper',
  'Tanker',
  'Dolly'
] as const;

// 1. Definición estricta de la física del JSONB
export type VehicleMetadata = {
  vin: string;
  year: number;
  make_model: string;
  nickname: string;
};

export type ComplianceRecords = {
  insurance_provider: string;
  policy_expiry: string;
  service_history_url?: string;
};

// 2. Extracción limpia de la tabla generada
type OriginalAssetRow = Database['public']['Tables']['assets']['Row'];
type OriginalAssetInsert = Database['public']['Tables']['assets']['Insert'];

// 3. Sobrescritura aislada (Exportamos esto para que lo use React Query)
export type AssetRow = Omit<OriginalAssetRow, 'vehicle_metadata' | 'compliance_records'> & {
  vehicle_metadata: VehicleMetadata;
  compliance_records: ComplianceRecords;
};

export type AssetInsert = Omit<OriginalAssetInsert, 'vehicle_metadata' | 'compliance_records'> & {
  vehicle_metadata: VehicleMetadata;
  compliance_records: ComplianceRecords;
};

// Exportamos el Database original intacto para el cliente de red
export type { Database };
