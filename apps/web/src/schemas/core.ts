import { z } from 'zod';

export const ProfileSchema = z.object({
  id: z.string().uuid(),
  full_name: z.string().nullable(),
  role: z.enum(['super_admin', 'fleet_manager', 'supervisor', 'driver']).nullable(),
  company_id: z.string().uuid().nullable(),
  status: z.string().default('active'),
});
export type Profile = z.infer<typeof ProfileSchema>;

export const ProjectSchema = z.object({
  id: z.string().uuid(),
  name: z.string().min(1, 'Project name is required'),
  client_name: z.string().nullable(),
  project_type: z.enum(['short_term', 'long_term']).nullable(),
  start_date: z.string().nullable(),
  estimated_end_date: z.string().nullable(),
  status: z.string().default('planning'),
  created_at: z.string(),
});
export type Project = z.infer<typeof ProjectSchema>;

export const ProjectMemberSchema = z.object({
  project_id: z.string().uuid(),
  user_id: z.string().uuid(),
  role: z.string().nullable(),
});
export type ProjectMember = z.infer<typeof ProjectMemberSchema>;

export const AssetSchema = z.object({
  id: z.string().uuid(),
  asset_code: z.string().min(1, 'Asset code is required'),
  registration_number: z.string().min(1, 'Registration number is required for NHVR'),
  fleet_manager_id: z.string().uuid(),
  current_project_id: z.string().uuid().nullable(),
  asset_type: z.string(),
  status: z.string().default('available'),
  is_compliant: z.boolean().default(false),
  last_odometer_checkin: z.number().default(0),
  created_at: z.string(),
});
export type Asset = z.infer<typeof AssetSchema>;

export const HandoverSchema = z.object({
  target_user_id: z.string().uuid('El operario receptor es obligatorio'),
  pin: z.string()
    .length(4, 'El PIN debe tener exactamente 4 dígitos')
    .regex(/^\d+$/, 'El PIN solo puede contener números'),
  notes: z.string().optional(),
});
export type HandoverFormValues = z.infer<typeof HandoverSchema>;

export const HandoverLogSchema = z.object({
  id: z.string().uuid(),
  project_id: z.string().uuid().nullable(),
  outgoing_user_id: z.string().uuid().nullable(),
  incoming_user_id: z.string().uuid().nullable(),
  open_incidents_count: z.number().nullable(),
  signature_timestamp: z.string(),
  signed_by_pin: z.boolean().default(true),
});
export type HandoverLog = z.infer<typeof HandoverLogSchema>;

export const BusinessMetricsSchema = z.object({
  active_users: z.number(),
  active_projects: z.number(),
  projected_mrr: z.number(),
});
export type BusinessMetrics = z.infer<typeof BusinessMetricsSchema>;

// --- Kiosk Hydration Schemas (Zero-Trust) ---
const GeoJSONPolygonSchema = z.object({
    type: z.literal('Polygon'),
    coordinates: z.array(z.array(z.tuple([z.number(), z.number()])))
});

const TopologySchema = z.object({
    hrcw_polygon: GeoJSONPolygonSchema.nullable(),
    loading_pad_strict: GeoJSONPolygonSchema.nullable(),
    loading_pad_buffered: GeoJSONPolygonSchema.nullable()
});

const CrewMemberSchema = z.object({
    user_id: z.string().uuid(),
    full_name: z.string().min(1),
    pin_hash: z.string().min(10),
    pin_salt: z.string().min(10)
});

export const HydrationPayloadSchema = z.object({
    topology: TopologySchema,
    crew: z.array(CrewMemberSchema).min(1, "El proyecto no tiene personal asignado.")
});

export type HydrationPayload = z.infer<typeof HydrationPayloadSchema>;
