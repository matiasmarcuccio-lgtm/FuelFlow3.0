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
BEGIN
    -- Validar propiedad del turno
    SELECT driver_id, asset_id INTO v_driver_id, v_asset_id 
    FROM public.asset_assignments 
    WHERE id = p_assignment_id AND status = 'IN_PROGRESS';

    IF v_driver_id != auth.uid() THEN
        RAISE EXCEPTION 'Violación WHS: No puede finalizar un turno que no le pertenece o que ya está cerrado.';
    END IF;

    -- Validar entropía termodinámica (Odómetro)
    SELECT current_odometer INTO v_current_odometer
    FROM public.assets
    WHERE id = v_asset_id;

    IF p_final_odometer < v_current_odometer THEN
        RAISE EXCEPTION 'Violación Termodinámica: El odómetro final (%) no puede ser menor al odómetro actual (%).', p_final_odometer, v_current_odometer;
    END IF;

    -- Mutación atómica 1: Cerrar el turno
    UPDATE public.asset_assignments 
    SET status = 'COMPLETED', ended_at = NOW() 
    WHERE id = p_assignment_id;

    -- Mutación atómica 2: Actualizar contadores del camión
    UPDATE public.assets 
    SET current_odometer = p_final_odometer, current_engine_hours = p_final_engine_hours 
    WHERE id = v_asset_id;

    -- Invocación al módulo huérfano: Encolar facturación
    -- NOTA: queue_erp_outbox() es una función disparadora (TRIGGER), no puede ser invocada directamente.
    -- Se omite el PERFORM directo para evitar fallas en tiempo de ejecución. 
    -- La inserción debe delegarse al trigger sobre execution_certificates o inyectarse manualmente si corresponde.

    RETURN TRUE;
END;
$$;

COMMIT;
