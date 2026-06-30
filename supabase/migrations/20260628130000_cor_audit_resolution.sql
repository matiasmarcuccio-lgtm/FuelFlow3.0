-- Migración: Auditoría Forense y Corrective Actions

ALTER TABLE public.load_offers
  ADD COLUMN IF NOT EXISTS anomaly_resolution_reason TEXT,
  ADD COLUMN IF NOT EXISTS anomaly_resolution_tags TEXT[]; -- Almacenará tags de acción correctiva

-- No necesitamos RLS complejas aquí porque los administradores ya tienen acceso de UPDATE, 
-- pero el Command Center se asegurará de popular esto.
