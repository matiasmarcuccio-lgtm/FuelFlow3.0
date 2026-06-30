-- Migración: Torre de Control (Anomaly & OCR)

ALTER TABLE public.load_offers
  ADD COLUMN IF NOT EXISTS ocr_mass_extracted NUMERIC,
  ADD COLUMN IF NOT EXISTS anomaly_flag VARCHAR(50), -- 'MASS_MISMATCH', 'BLURRY_DOCKET', 'STALLED_GEOFENCE'
  ADD COLUMN IF NOT EXISTS anomaly_resolved_at TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS anomaly_resolved_by UUID REFERENCES public.profiles(id);

-- Para propósitos del MVP y la simulación del OCR, crearemos un Database Trigger (Inquisidor)
-- que emula el Edge Function directamente en Postgres. 
-- Si `loaded_gross_mass` termina en 9 (e.g. 42009), flaggear como MASS_MISMATCH.
-- De lo contrario, auto-aprobar (ocr_mass_extracted = loaded_gross_mass).

CREATE OR REPLACE FUNCTION public.simulate_docket_ocr()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Solo auditar cuando transiciona a IN_TRANSIT y hay una imagen de docket
  IF NEW.status = 'IN_TRANSIT' AND OLD.status != 'IN_TRANSIT' AND NEW.docket_image_path IS NOT NULL THEN
    
    -- Lógica Simulada de "OCR"
    IF NEW.loaded_gross_mass % 10 = 9 THEN
      -- Anomalía Simulada!
      NEW.ocr_mass_extracted := NEW.loaded_gross_mass - 500; -- Diferencia de 500kg
      NEW.anomaly_flag := 'MASS_MISMATCH';
    ELSE
      -- Match Perfecto!
      NEW.ocr_mass_extracted := NEW.loaded_gross_mass;
      NEW.anomaly_flag := NULL;
    END IF;

  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_simulate_docket_ocr ON public.load_offers;
CREATE TRIGGER trigger_simulate_docket_ocr
  BEFORE UPDATE ON public.load_offers
  FOR EACH ROW
  EXECUTE FUNCTION public.simulate_docket_ocr();
