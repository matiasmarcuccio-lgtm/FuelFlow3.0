-- Migración: Capa de Gobernanza y Configuración de Sistema

CREATE TABLE IF NOT EXISTS public.system_config (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Habilitar RLS pero permitir lectura a autenticados (y admins para editar)
ALTER TABLE public.system_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow authenticated reads on system_config"
  ON public.system_config FOR SELECT TO authenticated USING (true);
  
CREATE POLICY "Allow admin updates on system_config"
  ON public.system_config FOR ALL TO authenticated USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('FLEET_MANAGER', 'SUPER_ADMIN'))
  );

-- Configuración Inicial
INSERT INTO public.system_config (key, value) VALUES
  ('ocr_mass_variance_threshold_kg', '500'),
  ('shadow_sync_stale_timeout_mins', '60')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Actualizamos el trigger del Inquisidor
CREATE OR REPLACE FUNCTION simulate_docket_ocr()
RETURNS TRIGGER AS $$
DECLARE
  variance_threshold INT;
BEGIN
  -- Leer la tolerancia de la tabla de configuración
  SELECT (value::text)::int INTO variance_threshold 
  FROM system_config 
  WHERE key = 'ocr_mass_variance_threshold_kg';
  
  -- Fallback en caso de que la config no exista
  IF variance_threshold IS NULL THEN
    variance_threshold := 500;
  END IF;

  -- Si el conductor usa el Override de Emergencia, esto ya se seteó a DRIVER_EMERGENCY_OVERRIDE.
  -- No sobreescribimos si ya viene con anomalía de override.
  IF NEW.anomaly_flag = 'DRIVER_EMERGENCY_OVERRIDE' THEN
    RETURN NEW;
  END IF;

  -- Solo evaluar cuando se transiciona a IN_TRANSIT (salida)
  IF NEW.status = 'IN_TRANSIT' AND OLD.status != 'IN_TRANSIT' AND NEW.docket_image_path IS NOT NULL THEN
    
    -- Lógica Simulada: Si termina en 9, asumimos error o engaño detectado
    IF NEW.loaded_gross_mass % 10 = 9 THEN
      NEW.ocr_mass_extracted := NEW.loaded_gross_mass - variance_threshold;
      NEW.anomaly_flag := 'MASS_MISMATCH';
    ELSE
      -- Si es legal
      NEW.ocr_mass_extracted := NEW.loaded_gross_mass;
    END IF;
    
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
