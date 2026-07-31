BEGIN;

CREATE OR REPLACE FUNCTION public.fn_cabin_end_shift(
    p_assignment_id UUID,
    p_final_odometer NUMERIC,
    p_final_engine_hours NUMERIC
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_driver_id UUID;
    v_asset_id UUID;
    v_current_odometer NUMERIC;
    v_current_engine_hours NUMERIC;
BEGIN
    SELECT driver_id, asset_id INTO v_driver_id, v_asset_id 
    FROM public.asset_assignments 
    WHERE id = p_assignment_id AND status = 'IN_PROGRESS';

    IF v_driver_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'Violación WHS: No puede finalizar un turno que no le pertenece o que ya está cerrado.';
    END IF;

    SELECT current_odometer, current_engine_hours INTO v_current_odometer, v_current_engine_hours
    FROM public.assets
    WHERE id = v_asset_id;

    IF p_final_odometer < v_current_odometer THEN
        RAISE EXCEPTION 'Fraude de Telemetría: El odómetro final (%) no puede ser menor a la lectura de inicio (%).', p_final_odometer, v_current_odometer;
    END IF;

    IF p_final_engine_hours < v_current_engine_hours THEN
        RAISE EXCEPTION 'Fraude de Telemetría: El horómetro final (%) no puede ser menor a la lectura de inicio (%).', p_final_engine_hours, v_current_engine_hours;
    END IF;

    UPDATE public.asset_assignments 
    SET status = 'COMPLETED', ended_at = NOW() 
    WHERE id = p_assignment_id;

    UPDATE public.assets 
    SET current_odometer = p_final_odometer, current_engine_hours = p_final_engine_hours 
    WHERE id = v_asset_id;

    -- ELIMINADO: PERFORM public.queue_erp_outbox(p_assignment_id);
    -- La responsabilidad de la cabina termina aquí.
    
    RETURN TRUE;
END;
$$;

COMMIT;
