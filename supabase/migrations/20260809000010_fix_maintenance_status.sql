CREATE OR REPLACE FUNCTION public.fn_export_regulatory_report(
    p_report_type VARCHAR(30) -- 'ATO_FUEL_REBATE', 'WHS_FATIGUE_AUDIT', 'PREDICTIVE_MAINTENANCE'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_role VARCHAR(50);
    v_caller_fleet UUID;
    v_result JSONB;
BEGIN
    SELECT role, fleet_id INTO v_caller_role, v_caller_fleet 
    FROM public.profiles WHERE id = auth.uid();

    IF v_caller_role NOT IN ('super_admin', 'fleet_manager') THEN
        RAISE EXCEPTION 'JURISDICCIÓN DENEGADA: Solo gerencia puede generar paquetes de auditoría legal.'
            USING ERRCODE = '42501';
    END IF;

    -- Refrescar vistas en segundo plano antes de la consulta (Garantía forense de datos al segundo)
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_ato_fuel_rebate_ledger;
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_predictive_maintenance_roster;
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_whs_compliance_audit;

    IF p_report_type = 'ATO_FUEL_REBATE' THEN
        SELECT jsonb_agg(to_jsonb(r.*)) INTO v_result
        FROM public.mv_ato_fuel_rebate_ledger r
        WHERE r.fleet_id = v_caller_fleet;
        
    ELSIF p_report_type = 'WHS_FATIGUE_AUDIT' THEN
        SELECT jsonb_agg(to_jsonb(w.*)) INTO v_result
        FROM public.mv_whs_compliance_audit w
        WHERE w.fleet_id = v_caller_fleet;
        
    ELSIF p_report_type = 'PREDICTIVE_MAINTENANCE' THEN
        SELECT jsonb_agg(to_jsonb(m.*)) INTO v_result
        FROM public.mv_predictive_maintenance_roster m
        WHERE m.fleet_id = v_caller_fleet;
    ELSE
        RAISE EXCEPTION 'INVALID_REPORT_TYPE: % no existe en el catálogo de exportación.', p_report_type
            USING ERRCODE = '22023';
    END IF;

    -- Asentar en el libro mayor que se emitió un documento legal (Trazabilidad WORM)
    INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
    VALUES (
        NULL,
        'EXPORTACIÓN FORENSE GENERADA [' || p_report_type || '] POR USUARIO ' || auth.uid(),
        auth.uid(),
        'resolved'
    );

    RETURN jsonb_build_object(
        'success', true,
        'report_type', p_report_type,
        'fleet_id', v_caller_fleet,
        'generated_at', now(),
        'data', COALESCE(v_result, '[]'::jsonb)
    );
END;
$$;
CREATE OR REPLACE FUNCTION public.fn_execute_shift_action(p_action VARCHAR(50), p_asset_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_uid UUID;
    v_caller_role VARCHAR(50);
    v_caller_fleet UUID;
    v_shift RECORD;
    v_asset_status VARCHAR(50);
    v_now TIMESTAMPTZ := now();
    v_elapsed_seconds INT;
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN RAISE EXCEPTION 'SESIÓN FANTASMA: Petición anónima bloqueada por Zero-Trust.' USING ERRCODE = '28000'; END IF;

    SELECT role, fleet_id INTO v_caller_role, v_caller_fleet FROM public.profiles WHERE id = v_caller_uid;

    -- Obtener turno activo si existe
    SELECT * INTO v_shift FROM public.shift_logs 
    WHERE operator_uid = v_caller_uid AND status IN ('ACTIVE', 'FATIGUE_LOCKOUT', 'BREAK_MANDATORY')
    ORDER BY created_at DESC LIMIT 1 FOR UPDATE;

    IF p_action = 'START_SHIFT' THEN
        IF v_shift IS NOT NULL THEN RAISE EXCEPTION 'WHS_VIOLATION: Ya existe un turno activo para este operador.' USING ERRCODE = '23505'; END IF;
        
        -- Insertar turno inmutable
        INSERT INTO public.shift_logs (operator_uid, fleet_id, asset_id, status)
        VALUES (v_caller_uid, v_caller_fleet, p_asset_id, 'ACTIVE')
        RETURNING id INTO v_shift.id;

        RETURN jsonb_build_object('success', true, 'action', p_action, 'shift_id', v_shift.id, 'status', 'ACTIVE');
    
    ELSIF p_action = 'CHECK_STATUS' THEN
        IF v_shift IS NULL THEN RAISE EXCEPTION 'NO_ACTIVE_SHIFT' USING ERRCODE = '02000'; END IF;

        -- Evaluar Guillotina de Fatiga (WorkSafe Tasmania: Max 5 hrs continuas, simularemos 5 hrs como 18000s)
        IF v_shift.status = 'ACTIVE' THEN
            v_elapsed_seconds := EXTRACT(EPOCH FROM (v_now - v_shift.last_state_change_at))::INT;
            
            IF (v_shift.continuous_work_seconds + v_elapsed_seconds) >= 18000 THEN
                -- EJECUCIÓN DE GUILLOTINA FÍSICA
                UPDATE public.shift_logs 
                SET status = 'FATIGUE_LOCKOUT', 
                    accumulated_work_seconds = accumulated_work_seconds + v_elapsed_seconds,
                    continuous_work_seconds = continuous_work_seconds + v_elapsed_seconds,
                    last_state_change_at = v_now
                WHERE id = v_shift.id;

                -- Enclavamiento Físico del Vehículo (Si aplica)
                IF v_shift.asset_id IS NOT NULL THEN
                    UPDATE public.assets SET status = 'maintenance', updated_at = v_now WHERE id = v_shift.asset_id;
                    
                    -- Alerta automática al Fleet Manager
                    INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
                    VALUES (v_shift.asset_id, 'ALERTA FATIGA WHS: UID ' || v_caller_uid || ' BLOQUEADO POR EXCEDER HORAS MÁXIMAS.', v_caller_uid, 'in_progress');
                END IF;

                RETURN jsonb_build_object('success', false, 'status', 'FATIGUE_LOCKOUT', 'msg', 'INTERLOCK ACTIVADO POR EXCESO DE FATIGA.');
            END IF;
        END IF;

        RETURN jsonb_build_object('success', true, 'status', v_shift.status, 'continuous_seconds', v_shift.continuous_work_seconds);

    ELSIF p_action = 'END_SHIFT' THEN
        IF v_shift IS NULL THEN RAISE EXCEPTION 'NO_ACTIVE_SHIFT' USING ERRCODE = '02000'; END IF;

        v_elapsed_seconds := EXTRACT(EPOCH FROM (v_now - v_shift.last_state_change_at))::INT;

        UPDATE public.shift_logs 
        SET status = 'COMPLETED',
            accumulated_work_seconds = accumulated_work_seconds + v_elapsed_seconds,
            continuous_work_seconds = continuous_work_seconds + v_elapsed_seconds,
            ended_at = v_now
        WHERE id = v_shift.id;

        -- Liberar la máquina si estaba bloqueada solo por fatiga
        IF v_shift.asset_id IS NOT NULL AND v_shift.status = 'FATIGUE_LOCKOUT' THEN
            UPDATE public.assets SET status = 'operational', updated_at = v_now WHERE id = v_shift.asset_id;
        END IF;

        RETURN jsonb_build_object('success', true, 'status', 'COMPLETED');
    ELSE
        RAISE EXCEPTION 'ACCIÓN NO RECONOCIDA: %', p_action USING ERRCODE = '22023';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_submit_fuel_log(
    p_asset_id UUID,
    p_liters_filled NUMERIC,
    p_engine_hours NUMERIC,
    p_cost_per_liter NUMERIC DEFAULT 1.85,
    p_location_tag VARCHAR(100) DEFAULT 'PIT_STATION'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_uid UUID;
    v_caller_fleet UUID;
    v_asset RECORD;
    v_last_log RECORD;
    v_status VARCHAR(50) := 'VERIFIED';
    v_hours_elapsed NUMERIC := 0;
    v_burn_rate NUMERIC := 0;
    v_tonnage NUMERIC := 0;
    v_now TIMESTAMPTZ := now();
    v_cost NUMERIC;
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN RAISE EXCEPTION 'SESIÓN FANTASMA: Petición anónima bloqueada por Zero-Trust.' USING ERRCODE = '28000'; END IF;

    SELECT fleet_id INTO v_caller_fleet FROM public.profiles WHERE id = v_caller_uid;

    -- Bloqueo atómico del activo
    SELECT * INTO v_asset FROM public.assets WHERE id = p_asset_id FOR UPDATE;
    IF v_asset IS NULL THEN RAISE EXCEPTION 'ACTIVO INVÁLIDO' USING ERRCODE = '22023'; END IF;
    IF v_asset.fleet_id != v_caller_fleet THEN RAISE EXCEPTION 'JURISDICCIÓN DENEGADA' USING ERRCODE = '42501'; END IF;

    -- Evitar viaje en el tiempo del horómetro
    IF p_engine_hours < COALESCE(v_asset.current_engine_hours, 0) THEN
        RAISE EXCEPTION 'ODOMETER_TAMPERING: Las horas (%s) no pueden ser menores al registro actual (%s).', p_engine_hours, v_asset.current_engine_hours
            USING ERRCODE = '22003';
    END IF;

    -- Buscar último repostaje de la máquina para cruzar datos
    SELECT * INTO v_last_log FROM public.fuel_logs 
    WHERE asset_id = p_asset_id ORDER BY created_at DESC LIMIT 1;

    -- Motor Forense de Triangulación
    v_hours_elapsed := p_engine_hours - COALESCE(v_last_log.engine_hours_at_fill, v_asset.current_engine_hours);
    v_cost := ROUND(p_liters_filled * p_cost_per_liter, 2);

    IF v_hours_elapsed > 0 THEN
        v_burn_rate := ROUND(p_liters_filled / v_hours_elapsed, 2);
        
        -- Cruzar con el tonelaje movido en ese intervalo temporal (Conducto 2)
        SELECT COALESCE(SUM(tonnage_moved), 0) INTO v_tonnage
        FROM public.haul_cycles
        WHERE asset_id = p_asset_id 
        AND created_at >= COALESCE(v_last_log.created_at, v_now - interval '1 year');

        -- Detección Algorítmica de Fraude y Rendimiento
        IF v_tonnage = 0 AND p_liters_filled > 50 THEN
            v_status := 'THEFT_SUSPECTED'; -- Se llenó el tanque pero el camión no movió tierra. Robo o sifón probable.
        ELSIF v_burn_rate > (v_asset.baseline_burn_rate_lph * 1.25) THEN
            v_status := 'ANOMALY_HIGH_BURN'; -- Supera la tolerancia mecánica del 25%
        ELSIF v_tonnage = 0 AND v_hours_elapsed > 2 THEN
            v_status := 'ANOMALY_IDLE_BURN'; -- El motor estuvo encendido sin producir. (Peligroso en la mina).
        END IF;
    ELSE
        -- No se movió el camión. Si inyectan mucho diésel, es fraude.
        IF p_liters_filled > 50 THEN v_status := 'THEFT_SUSPECTED'; END IF;
    END IF;

    -- Sellar el registro en el WORM Ledger
    INSERT INTO public.fuel_logs (asset_id, fleet_id, operator_uid, liters_filled, total_cost, burn_rate_lph, engine_hours_at_fill, tonnage_moved_since_last_fill, status)
    VALUES (p_asset_id, v_caller_fleet, v_caller_uid, p_liters_filled, v_cost, v_burn_rate, p_engine_hours, v_tonnage, v_status);

    -- Actualizar el estado de la máquina
    UPDATE public.assets SET current_engine_hours = p_engine_hours, updated_at = v_now WHERE id = p_asset_id;

    -- Alerta automática si hay anomalía grave
    IF v_status IN ('THEFT_SUSPECTED', 'ANOMALY_HIGH_BURN') THEN
        INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
        VALUES (
            p_asset_id, 
            'TELEMETRÍA CRÍTICA: ' || v_status || ' (' || p_liters_filled || 'L inyectados sin producción justificada)', 
            v_caller_uid, 
            'in_progress'
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'status', v_status,
        'liters_filled', p_liters_filled,
        'burn_rate_lph', v_burn_rate,
        'hours_elapsed', v_hours_elapsed,
        'tonnage_cross_ref', v_tonnage,
        'total_cost', v_cost,
        'timestamp', v_now
    );
END;
$$;
