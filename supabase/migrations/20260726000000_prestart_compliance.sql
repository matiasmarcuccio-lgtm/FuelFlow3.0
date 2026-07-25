-- Migración: Pre-Start Compliance (Fricción Temporal y Bifurcación) PARTE 1

-- 1. Ampliación del Estado del Turno en Asignaciones
ALTER TYPE public.assignment_status ADD VALUE IF NOT EXISTS 'pending_prestart';
ALTER TYPE public.assignment_status ADD VALUE IF NOT EXISTS 'in_progress';
