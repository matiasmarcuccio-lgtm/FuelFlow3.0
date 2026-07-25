-- 1. El Motor Predictivo en Capa 0 (SQL)
CREATE OR REPLACE FUNCTION public.calculate_fleet_health_scores(p_fleet_id UUID)
RETURNS TABLE (
    asset_id UUID,
    internal_code VARCHAR,
    health_score NUMERIC,
    critical_warnings INT,
    predicted_failure_days INT
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH thermal_stress AS (
        -- Cuenta los picos térmicos menores a 105°C pero mayores a 95°C en los últimos 14 días
        SELECT m.asset_id, count(*) as stress_events
        FROM public.iot_telemetry_logs m
        WHERE m.temperature BETWEEN 95 AND 104
        AND m.created_at >= (now() - interval '14 days')
        GROUP BY m.asset_id
    ),
    minor_defects AS (
        -- Cuenta defectos marcados en Pre-Starts que no bloquearon la máquina
        SELECT a.asset_id, count(*) as defect_events
        FROM public.prestart_inspections a
        WHERE a.status = 'passed_with_warnings'
        AND a.created_at >= (now() - interval '14 days')
        GROUP BY a.asset_id
    )
    SELECT 
        ast.id,
        ast.internal_code,
        -- Cálculo del Health Score (Base 100)
        GREATEST(0, 100 - (COALESCE(ts.stress_events, 0) * 4.5) - (COALESCE(md.defect_events, 0) * 2.0))::NUMERIC as health_score,
        (COALESCE(ts.stress_events, 0) + COALESCE(md.defect_events, 0))::INT as critical_warnings,
        -- Predicción lineal simple de falla
        CASE 
            WHEN (COALESCE(ts.stress_events, 0) + COALESCE(md.defect_events, 0)) = 0 THEN 90
            ELSE GREATEST(1, (30 / (COALESCE(ts.stress_events, 0) + COALESCE(md.defect_events, 0))))::INT
        END as predicted_failure_days
    FROM public.assets ast
    LEFT JOIN thermal_stress ts ON ast.id = ts.asset_id
    LEFT JOIN minor_defects md ON ast.id = md.asset_id
    WHERE ast.fleet_id = p_fleet_id;
END;
$$;

-- 2. Secuestro Diferido (Deferred Lock)
CREATE OR REPLACE FUNCTION public.lock_asset_preventively(p_asset_id UUID, p_reason TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_actor_role TEXT;
BEGIN
    v_actor_role := current_setting('request.jwt.claims', true)::jsonb ->> 'user_role';

    -- Escudo Jurisdiccional: Solo mecánicos y gerentes pueden interceptar
    IF v_actor_role NOT IN ('fitter', 'fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'WHS_UNAUTHORIZED: Solo el personal de taller puede ordenar un secuestro preventivo.';
    END IF;

    -- Transacción Atómica: Cambia el estado del activo (bloqueando nuevos Pre-Starts)
    -- y deja un registro en la bitácora forense.
    UPDATE public.assets
    SET status = 'maintenance'
    WHERE id = p_asset_id AND status = 'available';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_VIOLATION: El activo ya está secuestrado o no existe.';
    END IF;

    INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
    VALUES (p_asset_id, '[PREDICTIVO] ' || p_reason, auth.uid(), 'open');
END;
$$;
