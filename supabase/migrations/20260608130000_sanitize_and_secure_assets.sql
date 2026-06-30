-- Migración de Integridad: Sanear registros históricos y sellar el RLS de la tabla assets

-- 1. Saneamiento Histórico: Forzar geometría JSONB estricta para Zod
UPDATE public.assets
SET 
  vehicle_metadata = COALESCE(
    vehicle_metadata, 
    '{"vin": "PENDIENTEDEACTUAL", "year": 2000, "make_model": "Sin Registrar", "nickname": ""}'::jsonb
  ),
  compliance_records = COALESCE(
    compliance_records,
    '{"insurance_provider": "Sin Registrar", "policy_expiry": "2026-01-01"}'::jsonb
  ),
  is_nhvr_accredited = COALESCE(is_nhvr_accredited, false);

-- 2. Sellar Políticas RLS de 360 Grados
ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;

-- Select Policy
DROP POLICY IF EXISTS "Assets_Select" ON public.assets;
CREATE POLICY "Assets_Select" ON public.assets 
FOR SELECT 
USING (fleet_id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid()));

-- Insert Policy
DROP POLICY IF EXISTS "Assets_Insert" ON public.assets;
CREATE POLICY "Assets_Insert" ON public.assets 
FOR INSERT 
WITH CHECK (fleet_id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid()));

-- Update Policy
DROP POLICY IF EXISTS "Assets_Update" ON public.assets;
CREATE POLICY "Assets_Update" ON public.assets 
FOR UPDATE 
USING (fleet_id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid()));

-- Delete Policy
DROP POLICY IF EXISTS "Assets_Delete" ON public.assets;
CREATE POLICY "Assets_Delete" ON public.assets 
FOR DELETE 
USING (fleet_id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid()));
