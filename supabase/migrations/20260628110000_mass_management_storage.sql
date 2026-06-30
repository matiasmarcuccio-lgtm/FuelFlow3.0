-- Migración: Gestión de Masa y Tíquet Digital (Digital Docketing)

-- 1. Crear la tabla de Vehículos vinculada al Perfil (Conductor)
CREATE TABLE IF NOT EXISTS public.vehicles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  registration_plate VARCHAR(20) NOT NULL,
  tare_weight NUMERIC NOT NULL, -- Peso vacío en kg
  gvm_limit NUMERIC NOT NULL,   -- Límite legal (Gross Vehicle Mass) en kg
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- RLS para Vehicles
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Conductores pueden ver sus propios vehículos"
  ON public.vehicles FOR SELECT
  USING (auth.uid() = profile_id);

CREATE POLICY "Administradores pueden gestionar vehículos"
  ON public.vehicles FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role IN ('ADMIN', 'FLEET_MANAGER')
    )
  );

-- 2. Modificar load_offers para soportar la trazabilidad de masa y material
ALTER TABLE public.load_offers
  ADD COLUMN IF NOT EXISTS material_type VARCHAR(50),
  ADD COLUMN IF NOT EXISTS is_hazardous BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS waste_certificate_id VARCHAR(100),
  ADD COLUMN IF NOT EXISTS loaded_gross_mass NUMERIC,
  ADD COLUMN IF NOT EXISTS docket_image_path TEXT;

-- Añadir el estado 'LOADING' a load_offers.status 
-- (Al ser VARCHAR, solo necesitamos asegurarnos de que la aplicación lo entienda, pero si fuera ENUM tocaría ALTER TYPE)

-- 3. Crear el Bucket Inmutable en Storage
INSERT INTO storage.buckets (id, name, public) 
VALUES ('docket_evidence', 'docket_evidence', false)
ON CONFLICT (id) DO NOTHING;

-- RLS de Storage: Insert-Only
-- Cualquier usuario autenticado puede subir una foto
CREATE POLICY "Conductores pueden subir evidencia de tíquet"
  ON storage.objects FOR INSERT 
  TO authenticated
  WITH CHECK ( bucket_id = 'docket_evidence' );

-- Los administradores/inspectores pueden verla
CREATE POLICY "Lectura de evidencia"
  ON storage.objects FOR SELECT
  TO authenticated
  USING ( bucket_id = 'docket_evidence' );

-- ESTRICTAMENTE PROHIBIDO el UPDATE o DELETE en 'docket_evidence'
-- (Al no definir políticas para UPDATE/DELETE, Postgres lo deniega por defecto)
