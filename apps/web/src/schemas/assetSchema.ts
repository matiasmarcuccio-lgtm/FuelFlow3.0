import { z } from 'zod';
import { ASSET_TYPES, TRAILER_TYPES } from '@fuelflow/shared-types';

export type AssetFormInput = z.input<typeof assetSchema>;
export type AssetFormData = z.output<typeof assetSchema>;

export const assetSchema = z.object({
  asset_type: z.enum(ASSET_TYPES),
  trailer_type: z.enum(TRAILER_TYPES).nullable(),
  max_payload_kg: z.union([z.string(), z.number()])
    .transform(v => Number(v))
    .pipe(z.number().positive('Debe ser un peso mayor a 0'))
    .nullable(),
  pallet_capacity: z.union([z.string(), z.number()])
    .transform(v => Number(v))
    .pipe(z.number().int().positive('Debe ser un número entero'))
    .nullable(),
  is_nhvr_accredited: z.boolean().default(false),
  vehicle_metadata: z.object({
    vin: z.string().length(17, 'El VIN requiere exactamente 17 caracteres'),
    year: z.union([z.string(), z.number()])
      .transform(v => Number(v))
      .pipe(z.number().min(1990).max(new Date().getFullYear() + 1)),
    make_model: z.string().min(1, 'La marca y modelo son obligatorios'),
    nickname: z.string().default('')
  }),
  compliance_records: z.any().default({})
}).strict();
