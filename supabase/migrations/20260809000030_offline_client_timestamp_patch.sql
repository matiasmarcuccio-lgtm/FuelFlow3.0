-- ============================================================================
-- PARCHE DE RESILIENCIA OFFLINE: MARCAS DE TIEMPO DEL CLIENTE
-- Para evitar que un camión que descarga a las 14:00 pero recupera señal 4G a 
-- las 14:45 registre la hora del servidor (dañando el cálculo de Toneladas x Hora),
-- reemplazamos `v_now := now()` por `COALESCE(p_client_timestamp, now())`.
-- ============================================================================

-- REEMPLAZO 1: Motor de Despacho (fn_execute_haul_transition)
CREATE OR REPLACE FUNCTION public.fn_execute_haul_transition(
    p_asset_id UUID,
    p_action VARCHAR(20),
    p_route_id UUID DEFAULT NULL,
    p_material_id UUID DEFAULT NULL,
    p_client_timestamp TIMESTAMPTZ DEFAULT NULL -- PARCHE AÑADIDO
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_uid UUID := auth.uid();
    v_shift RECORD; v_cycle RECORD; v_asset RECORD; v_material RECORD;
    v_calc_tonnage NUMERIC(8,2) := 0.00;
    
    -- El servidor respeta la marca de tiempo de IndexedDB enviada por la cabina.
    -- Si no existe (ataque o error), usa now().
    v_now TIMESTAMPTZ := COALESCE(p_client_timestamp, now());
BEGIN
    -- Validaciones estándar de aduana...
    IF v_caller_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

    SELECT id, fleet_id, status INTO v_shift FROM public.shift_logs 
    WHERE operator_uid = v_caller_uid AND status = 'ACTIVE' ORDER BY started_at DESC LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'WHS_INTERLOCK'; END IF;

    SELECT id, fleet_id, status, hopper_capacity_m3 INTO v_asset 
    FROM public.assets WHERE id = p_asset_id FOR UPDATE;

    SELECT * INTO v_cycle FROM public.haul_cycles 
    WHERE asset_id = p_asset_id AND state NOT IN ('COMPLETED', 'ABORTED') FOR UPDATE;

    IF p_action = 'START_LOADING' THEN
        INSERT INTO public.haul_cycles (fleet_id, asset_id, operator_uid, shift_id, route_id, material_id, state, started_at)
        VALUES (v_shift.fleet_id, p_asset_id, v_caller_uid, v_shift.id, p_route_id, p_material_id, 'LOADING', v_now)
        RETURNING * INTO v_cycle;
        UPDATE public.assets SET status = 'DISPATCHED', updated_at = v_now WHERE id = p_asset_id;
        RETURN jsonb_build_object('success', true, 'state', 'LOADING', 'started_at', v_now);
        
    ELSIF p_action = 'FINISH_LOADING' THEN
        SELECT density_kg_m3 INTO v_material FROM public.materials WHERE id = v_cycle.material_id;
        IF FOUND THEN v_calc_tonnage := (COALESCE(v_asset.hopper_capacity_m3, 18.00) * v_material.density_kg_m3) / 1000.0; END IF;
        
        UPDATE public.haul_cycles SET state = 'HAULING', loaded_at = v_now, tonnage_moved = v_calc_tonnage WHERE id = v_cycle.id;
        RETURN jsonb_build_object('success', true, 'state', 'HAULING', 'tonnage_moved', v_calc_tonnage);
        
    ELSIF p_action = 'CONFIRM_DUMP' THEN
        UPDATE public.haul_cycles SET state = 'RETURNING', dumped_at = v_now WHERE id = v_cycle.id;
        RETURN jsonb_build_object('success', true, 'state', 'RETURNING', 'dumped_at', v_now);
        
    ELSIF p_action = 'COMPLETE_CYCLE' THEN
        UPDATE public.haul_cycles 
        SET state = 'COMPLETED', completed_at = v_now,
            cycle_duration_seconds = GREATEST(1, EXTRACT(EPOCH FROM (v_now - v_cycle.started_at))::INT)
        WHERE id = v_cycle.id;
        UPDATE public.assets SET status = 'AVAILABLE', updated_at = v_now WHERE id = p_asset_id;
        RETURN jsonb_build_object('success', true, 'state', 'COMPLETED', 'tonnage_added', v_cycle.tonnage_moved);
        
    ELSIF p_action = 'ABORT' THEN
        UPDATE public.haul_cycles SET state = 'ABORTED', completed_at = v_now WHERE id = v_cycle.id;
        UPDATE public.assets SET status = 'AVAILABLE', updated_at = v_now WHERE id = p_asset_id;
        RETURN jsonb_build_object('success', true, 'state', 'ABORTED');
    END IF;
    
    RAISE EXCEPTION 'UNKNOWN_ACTION';
END;
$$;
