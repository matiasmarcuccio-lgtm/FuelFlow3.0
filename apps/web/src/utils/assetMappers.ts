import type { AssetRow } from '@fuelflow/shared-types';
import type { AssetFormInput } from '../schemas/assetSchema';

export function mapAssetRowToInput(row: AssetRow): AssetFormInput {
  // Evaluamos con seguridad total, bloqueando nulos y arreglos
  const metadata = typeof row.vehicle_metadata === 'object' && 
                   row.vehicle_metadata !== null && 
                   !Array.isArray(row.vehicle_metadata)
    ? (row.vehicle_metadata as Record<string, any>)
    : {};

  const compliance = typeof row.compliance_records === 'object' && 
                     row.compliance_records !== null && 
                     !Array.isArray(row.compliance_records)
    ? row.compliance_records
    : {};

  return {
    asset_type: row.asset_type as any,
    trailer_type: row.trailer_type as any,
    max_payload_kg: row.max_payload_kg,
    pallet_capacity: row.pallet_capacity,
    is_nhvr_accredited: row.is_nhvr_accredited ?? false,
    vehicle_metadata: {
      vin: metadata.vin ?? '',
      year: metadata.year ?? new Date().getFullYear(),
      make_model: metadata.make_model ?? '',
      nickname: metadata.nickname ?? ''
    },
    compliance_records: compliance
  };
}
