BEGIN;

CREATE OR REPLACE FUNCTION public.fn_cabin_accept_dispatch(
    p_assignment_id UUID,
    p_results JSONB,
    p_fatal BOOLEAN
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_asset_id UUID;
    v_fleet_id UUID;
    v_operator_id UUID;
BEGIN
    -- Identidad
    v_operator_id := auth.uid();

    -- Validar que la asignación existe y está DISPATCHED para este conductor
    SELECT asset_id, fleet_id INTO v_asset_id, v_fleet_id 
    FROM public.asset_assignments 
    WHERE id = p_assignment_id AND driver_id = v_operator_id AND status = 'DISPATCHED';

    IF v_asset_id IS NULL THEN
        RAISE EXCEPTION 'Violación de Turno: Asignación no encontrada o no se encuentra en estado DISPATCHED.';
    END IF;

    -- Registrar evidencia forense (Pre-Start Log)
    INSERT INTO public.whs_prestart_logs (asset_id, operator_uid, fleet_id, checklist_data, passed, client_timestamp)
    VALUES (v_asset_id, v_operator_id, v_fleet_id, p_results, NOT p_fatal, NOW());

    -- Triada de inmovilización o Aceptación
    IF p_fatal THEN
        -- 1. Mata el turno
        UPDATE public.asset_assignments SET status = 'REVOKED' WHERE id = p_assignment_id;
        
        -- 2. Aplica el candado WHS
        UPDATE public.assets SET status = 'MAINTENANCE' WHERE id = v_asset_id;

        -- 3. Convoca al mecánico
        INSERT INTO public.plant_defects (asset_id, reported_by, defect_description, status) 
        VALUES (v_asset_id, v_operator_id, 'Fallo crítico reportado en inspección Pre-Start (Automático)', 'OPEN');
        
        RETURN FALSE;
    ELSE
        -- Todo en orden, comienza el turno
        UPDATE public.asset_assignments SET status = 'IN_PROGRESS', prestart_commenced_at = NOW() WHERE id = p_assignment_id;
        
        RETURN TRUE;
    END IF;
END;
$$;

COMMIT;
