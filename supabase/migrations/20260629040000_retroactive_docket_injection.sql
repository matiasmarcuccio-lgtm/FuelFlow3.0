-- Migration: Retroactive Docket Injection (Evidence Vault)

-- 1. Modify load_offers table
ALTER TABLE public.load_offers 
ADD COLUMN IF NOT EXISTS digital_bypass BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS bypassed_by UUID REFERENCES auth.users(id),
ADD COLUMN IF NOT EXISTS paper_docket_ref VARCHAR(100),
ADD COLUMN IF NOT EXISTS docket_image_path VARCHAR(255);

-- 2. Modify trg_autoloop_on_complete trigger logic
CREATE OR REPLACE FUNCTION public.fn_trigger_autoloop()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_shift_assignment RECORD;
  v_master_order RECORD;
  v_total_delivered NUMERIC;
  v_is_completed_transition BOOLEAN := false;
BEGIN
  -- Determine if this is a valid completion transition
  IF TG_OP = 'INSERT' THEN
      v_is_completed_transition := (NEW.status = 'COMPLETED');
  ELSIF TG_OP = 'UPDATE' THEN
      v_is_completed_transition := (NEW.status = 'COMPLETED' AND OLD.status != 'COMPLETED');
  END IF;

  IF v_is_completed_transition THEN
    
    -- Si la oferta pertenece a un Master Order
    IF NEW.master_order_id IS NOT NULL THEN
      
      -- Obtener detalles del Master Order
      SELECT * INTO v_master_order FROM public.master_orders WHERE id = NEW.master_order_id;
      
      IF FOUND THEN
        -- Calcular tonelaje entregado total para esta orden
        SELECT COALESCE(SUM(COALESCE(ocr_mass_extracted, loaded_gross_mass)), 0) INTO v_total_delivered 
        FROM public.load_offers 
        WHERE master_order_id = NEW.master_order_id AND status = 'COMPLETED';

        -- Si no se ha alcanzado la meta, generar el siguiente ciclo
        IF v_total_delivered < v_master_order.target_tonnage THEN
          -- Solo insertar si no existe ya una orden PENDING para este conductor en este Master Order.
          IF NOT EXISTS (SELECT 1 FROM public.load_offers WHERE driver_id = NEW.driver_id AND master_order_id = NEW.master_order_id AND status = 'PENDING') THEN
            INSERT INTO public.load_offers (
              master_order_id,
              driver_id,
              status,
              material_type,
              requires_4x4_traction,
              max_turn_radius_m,
              created_at
            ) VALUES (
              v_master_order.id,
              NEW.driver_id,
              'PENDING',
              v_master_order.material_type,
              v_master_order.requires_4x4_traction,
              v_master_order.max_turn_radius_m,
              NOW()
            );
          END IF;
        ELSE
          -- Cerrar el Master Order y los Turnos
          UPDATE public.master_orders SET status = 'FULFILLED' WHERE id = v_master_order.id;
          UPDATE public.shift_assignments SET status = 'COMPLETED' WHERE master_order_id = v_master_order.id;
        END IF;
      END IF;
    END IF;
  END IF;

  -- Romper el bucle si hay avería
  IF TG_OP = 'UPDATE' THEN
    IF NEW.status = 'BREAKDOWN' THEN
      UPDATE public.shift_assignments SET status = 'SUSPENDED_BREAKDOWN' WHERE driver_id = NEW.driver_id AND status = 'ACTIVE';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Re-bind the trigger to both operations
DROP TRIGGER IF EXISTS trg_autoloop_on_complete ON public.load_offers;
CREATE TRIGGER trg_autoloop_on_complete
    AFTER INSERT OR UPDATE ON public.load_offers
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_trigger_autoloop();


-- 3. Create RPC Function for Evidence Vault Submission
CREATE OR REPLACE FUNCTION public.fn_inject_retroactive_docket(
    p_master_order_id UUID, 
    p_driver_id UUID, 
    p_loaded_gross_mass NUMERIC, 
    p_paper_docket_ref VARCHAR, 
    p_docket_image_path VARCHAR
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_inserted_id UUID;
BEGIN
    -- Validaciones
    IF p_master_order_id IS NULL OR p_driver_id IS NULL OR p_loaded_gross_mass IS NULL OR p_paper_docket_ref IS NULL OR p_docket_image_path IS NULL THEN
        RAISE EXCEPTION 'All forensic fields are mandatory for a Bypass Injection.';
    END IF;

    -- Authorization validation
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('FLEET_MANAGER', 'SUPER_ADMIN')) THEN
        RAISE EXCEPTION 'Unauthorized: Only Fleet Managers or Super Admins can inject bypass dockets.';
    END IF;

    INSERT INTO public.load_offers (
        master_order_id,
        driver_id,
        status,
        loaded_gross_mass,
        digital_bypass,
        bypassed_by,
        paper_docket_ref,
        docket_image_path,
        created_at,
        completed_at_local
    ) VALUES (
        p_master_order_id,
        p_driver_id,
        'COMPLETED',
        p_loaded_gross_mass,
        true,
        auth.uid(),
        p_paper_docket_ref,
        p_docket_image_path,
        NOW(),
        NOW()
    ) RETURNING id INTO v_inserted_id;

    RETURN v_inserted_id;
END;
$$;

-- 4. Storage Bucket Configuration
INSERT INTO storage.buckets (id, name, public) 
VALUES ('docket_evidence', 'docket_evidence', true)
ON CONFLICT (id) DO NOTHING;

-- Policies should be DROP IF EXISTS before CREATE but supabase uses distinct names, 
-- we will use DO IF NOT EXISTS blocks or just rely on the migration applying once.
-- We can ignore DROP policy here since it's a new bucket.

-- Storage RLS (Requires authenticated users)
CREATE POLICY "Authenticated users can upload docket evidence"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'docket_evidence' 
    AND EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('FLEET_MANAGER', 'SUPER_ADMIN'))
);

CREATE POLICY "Authenticated users can view docket evidence"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'docket_evidence');

-- 5. Update view_cor_audit_timeline
DROP VIEW IF EXISTS public.view_cor_audit_timeline;
CREATE VIEW public.view_cor_audit_timeline AS
SELECT 
    lo.id as load_id,
    lo.status,
    lo.anomaly_flag,
    lo.anomaly_resolution_reason,
    lo.anomaly_resolution_tags,
    lo.anomaly_resolved_at as resolved_at,
    lo.created_at,
    lo.completed_at_local,
    lo.digital_bypass,
    lo.paper_docket_ref,
    lo.docket_image_path,
    p1.full_name as operator_id,
    p2.full_name as bypassed_by_name
FROM public.load_offers lo
LEFT JOIN public.profiles p1 ON lo.driver_id = p1.id
LEFT JOIN public.profiles p2 ON lo.bypassed_by = p2.id
ORDER BY lo.created_at DESC;
