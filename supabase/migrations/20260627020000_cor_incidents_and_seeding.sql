-- 1. Crear tabla de incidentes
CREATE TABLE IF NOT EXISTS public.cor_incidents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  load_offer_id UUID NOT NULL REFERENCES public.load_offers(id) ON DELETE CASCADE,
  operator_id UUID NOT NULL REFERENCES public.profiles(id),
  description TEXT NOT NULL,
  gps_location POINT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. Habilitar RLS
ALTER TABLE public.cor_incidents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Operators can view incidents of their loads"
  ON public.cor_incidents FOR SELECT
  USING (
    operator_id = auth.uid() OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "Operators can insert incidents"
  ON public.cor_incidents FOR INSERT
  WITH CHECK (operator_id = auth.uid());

-- 3. Adjuntar el Trigger Forense a la tabla
CREATE TRIGGER on_cor_incident_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.cor_incidents
  FOR EACH ROW EXECUTE FUNCTION public.audit_log_changes();

-- 4. RPC para Reportar Incidente
CREATE OR REPLACE FUNCTION public.report_incident(
  p_offer_id UUID,
  p_description TEXT,
  p_lat NUMERIC,
  p_lng NUMERIC
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
  -- Verificar que la oferta está asignada a quien llama
  IF NOT EXISTS (
    SELECT 1 FROM public.assignments 
    WHERE load_offer_id = p_offer_id AND operator_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Solo el operador asignado puede reportar incidentes para esta carga.';
  END IF;

  INSERT INTO public.cor_incidents (load_offer_id, operator_id, description, gps_location)
  VALUES (
    p_offer_id,
    auth.uid(),
    p_description,
    point(p_lng, p_lat) -- Formato estándar de punto: (longitud, latitud)
  );
END;
$$;

-- 5. RPC Táctica: Seeding End-to-End
CREATE OR REPLACE FUNCTION public.seed_test_trip()
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_offer_id UUID;
  v_uid UUID;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado.';
  END IF;

  -- Crear una oferta de carga en estado OPEN
  INSERT INTO public.load_offers (
    contractor_id, 
    crane_window_start, 
    crane_window_end, 
    destination_lat, 
    destination_lng, 
    requires_4x4_traction, 
    status
  )
  VALUES (
    v_uid, 
    now(), 
    now() + interval '4 hours', 
    -33.8688, 
    151.2093, 
    false, 
    'MANIFEST_PENDING' -- Para probar directamente el dashboard de ActiveTrip
  )
  RETURNING id INTO v_offer_id;

  -- Crear la asignación al conductor (él mismo, para testing rápido)
  INSERT INTO public.assignments (
    load_offer_id,
    operator_id
  )
  VALUES (
    v_offer_id,
    v_uid
  );
END;
$$;
