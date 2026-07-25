-- 1. Inyectar memoria temporal en el turno
ALTER TABLE public.asset_assignments ADD COLUMN IF NOT EXISTS prestart_commenced_at TIMESTAMPTZ;

-- 2. Nuevo RPC: El Disparador del Reloj
-- Este RPC se llama de forma silenciosa en el instante en que el Kiosco se renderiza en la tablet.
CREATE OR REPLACE FUNCTION public.mark_prestart_commenced(p_assignment_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_record RECORD;
BEGIN
    v_caller_id := auth.uid();
    
    SELECT * INTO v_record FROM public.asset_assignments WHERE id = p_assignment_id FOR UPDATE;
    
    -- Validar jurisdicción
    IF v_record.driver_id != v_caller_id THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_UNAUTHORIZED: Solo el operador asignado puede iniciar la inspección.';
    END IF;
    
    -- Solo marcar si no ha sido marcado previamente (resiliencia ante recargas de página)
    IF v_record.prestart_commenced_at IS NULL THEN
        UPDATE public.asset_assignments 
        SET prestart_commenced_at = now() 
        WHERE id = p_assignment_id;
    END IF;
END;
$$;

-- 3. Reescribir el RPC de Certificación (Extirpando la confianza en el cliente)
DROP FUNCTION IF EXISTS public.certify_prestart(UUID, TIMESTAMPTZ, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, TEXT);

CREATE OR REPLACE FUNCTION public.certify_prestart(
    p_assignment_id UUID,
    p_brakes BOOLEAN,
    p_fluids BOOLEAN,
    p_structural BOOLEAN,
    p_is_safe BOOLEAN,
    p_defect_notes TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_assignment_record RECORD;
BEGIN
    v_caller_id := auth.uid();

    SELECT * INTO v_assignment_record 
    FROM public.asset_assignments 
    WHERE id = p_assignment_id FOR UPDATE;

    IF v_assignment_record.driver_id != v_caller_id THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_UNAUTHORIZED: Solo el operador asignado puede certificar el activo.';
    END IF;

    IF v_assignment_record.status != 'pending_prestart' THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_CONFLICT: El turno ya fue iniciado o cerrado.';
    END IF;

    -- Candado de Reloj del Servidor
    IF v_assignment_record.prestart_commenced_at IS NULL THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_VIOLATION: No se registró el inicio de la inspección en el servidor.';
    END IF;

    -- Aquí PostgreSQL evalúa prestart_time_friction usando SU propio reloj guardado
    INSERT INTO public.prestart_checks (
        assignment_id, operator_id, brakes_checked, fluids_checked, structural_checked, 
        is_safe_to_operate, defect_notes, inspection_started_at, inspection_completed_at
    ) VALUES (
        p_assignment_id, v_caller_id, p_brakes, p_fluids, p_structural, 
        p_is_safe, p_defect_notes, v_assignment_record.prestart_commenced_at, now()
    );

    IF p_is_safe THEN
        UPDATE public.asset_assignments 
        SET status = 'in_progress' 
        WHERE id = p_assignment_id;
    ELSE
        UPDATE public.asset_assignments 
        SET status = 'completed', shift_end = now() 
        WHERE id = p_assignment_id;
        
        UPDATE public.assets 
        SET status = 'maintenance' 
        WHERE id = v_assignment_record.asset_id;
        
        INSERT INTO public.maintenance_logs (asset_id, locked_by_uid, issue_description)
        VALUES (v_assignment_record.asset_id, v_caller_id, 'PRE-START FAILURE: ' || COALESCE(p_defect_notes, 'Unspecified hazard'));
    END IF;
END;
$$;
