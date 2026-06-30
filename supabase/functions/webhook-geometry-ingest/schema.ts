import { z } from 'https://deno.land/x/zod@v3.22.4/mod.ts';

export const GeometryPayloadSchema = z.object({
  project_id: z.string().uuid("Se requiere un UUID de proyecto válido"),
  zone_type: z.enum(['staging_area', 'active_excavation', 'exclusion_zone']),
  crs: z.object({
    type: z.literal('name'),
    properties: z.object({
      name: z.enum([
        'urn:ogc:def:crs:OGC:1.3:CRS84',
        'EPSG:4326'
      ], { errorMap: () => ({ message: "Rechazado: El CRS debe ser estrictamente EPSG:4326 (WGS 84) en formato Longitud/Latitud" }) })
    })
  }),
  geometry: z.object({
    type: z.literal('Polygon'),
    coordinates: z.array(
      z.array(
        z.array(z.number()).length(2, "Las coordenadas deben ser bidimensionales [long, lat]")
      ).min(4, "Un polígono cerrado requiere al menos 4 puntos físicos")
    )
  })
});

export type GeometryPayload = z.infer<typeof GeometryPayloadSchema>;
