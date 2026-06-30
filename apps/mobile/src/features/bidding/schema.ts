import { z } from 'zod';

// ESPEJO EXACTO DE POSTGRES (Fail-Fast Real)
export const LoadOfferSchema = z.object({
  // Identificador inyectado por el contexto de usuario
  contractor_id: z.string().uuid("ID de contratista inválido"),
  
  // Ventana de Operación Logística
  crane_window_start: z.string().datetime("Formato ISO requerido para inicio de grúa"),
  crane_window_end: z.string().datetime("Formato ISO requerido para fin de grúa"),
  
  // Geometría Estricta (Turf.js Edge Engine la usará)
  destination_lat: z.number().min(-90).max(90, "Latitud fuera de rango"),
  destination_lng: z.number().min(-180).max(180, "Longitud fuera de rango"),
  
  // Restricciones de Vehículo Pesado (HVNL)
  requires_4x4_traction: z.boolean().default(false),
  max_turn_radius_m: z.number().positive("El radio de giro debe ser positivo").optional(),
});

export type LoadOfferInput = z.infer<typeof LoadOfferSchema>;
