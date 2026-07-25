-- 1. VISTA MATERIALIZADA: LIBRO MAYOR TRIBUTARIO ATO (Créditos de Combustible)
CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_ato_fuel_rebate_ledger AS
SELECT 
    f.fleet_id,
    f.asset_id,
    a.internal_code AS asset_name,
    a.category AS asset_type,
    COUNT(f.id) AS total_refuels,
    SUM(f.liters_filled) AS total_liters_injected,
    SUM(f.total_cost) AS total_aud_spent,
    -- Tasa FTC estimada en $0.479 AUD por litro para uso pesado fuera de carretera en minería
    ROUND(SUM(f.liters_filled) * 0.479, 2) AS estimated_ato_rebate_aud,
    ROUND(AVG(f.burn_rate_lph), 2) AS avg_burn_rate_lph,
    SUM(f.tonnage_moved_since_last_fill) AS total_tonnage_associated,
    MAX(f.created_at) AS last_refuel_timestamp
FROM public.fuel_logs f
JOIN public.assets a ON f.asset_id = a.id
WHERE f.status != 'THEFT_SUSPECTED' -- El diésel robado no califica para crédito fiscal
GROUP BY f.fleet_id, f.asset_id, a.internal_code, a.category
WITH DATA;

-- Índice único para permitir la recarga concurrente (CONCURRENTLY) sin bloquear lecturas
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_ato_fuel_asset ON public.mv_ato_fuel_rebate_ledger(asset_id);

-- 2. VISTA MATERIALIZADA: ROSTER DE MANTENIMIENTO PREDICTIVO (Horómetros)
CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_predictive_maintenance_roster AS
SELECT 
    a.id AS asset_id,
    a.fleet_id,
    a.internal_code AS asset_name,
    a.status AS current_whs_status,
    a.current_engine_hours,
    -- Intervalo de servicio pesado estándar OEM: Cada 250 horas-motor
    (250.0 - MOD(a.current_engine_hours::numeric, 250.0)) AS hours_until_next_service,
    CASE 
        WHEN MOD(a.current_engine_hours::numeric, 250.0) >= 230.0 THEN 'URGENT_SERVICE_DUE'
        WHEN MOD(a.current_engine_hours::numeric, 250.0) >= 200.0 THEN 'SERVICE_WARNING'
        ELSE 'OPTIMAL_OPERATIONAL'
    END AS maintenance_priority,
    COUNT(l.id) AS active_danger_tags_count
FROM public.assets a
LEFT JOIN public.asset_lockouts l ON a.id = l.asset_id AND l.status = 'ACTIVE'
GROUP BY a.id, a.fleet_id, a.internal_code, a.status, a.current_engine_hours
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_maint_asset ON public.mv_predictive_maintenance_roster(asset_id);

-- 3. VISTA MATERIALIZADA: AUDITORÍA DE CUMPLIMIENTO WHS (WorkSafe Tasmania)
CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_whs_compliance_audit AS
SELECT 
    s.fleet_id,
    s.operator_uid,
    p.full_name AS operator_name,
    COUNT(s.id) AS total_shifts_worked,
    ROUND(SUM(s.accumulated_work_seconds) / 3600.0, 2) AS total_work_hours,
    ROUND(AVG(s.continuous_work_seconds) / 3600.0, 2) AS avg_continuous_drive_hours,
    SUM(CASE WHEN s.status = 'FATIGUE_LOCKOUT' THEN 1 ELSE 0 END) AS fatigue_lockouts_triggered,
    MAX(s.started_at) AS last_shift_start
FROM public.shift_logs s
JOIN public.profiles p ON s.operator_uid = p.id
GROUP BY s.fleet_id, s.operator_uid, p.full_name
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_whs_operator ON public.mv_whs_compliance_audit(operator_uid);

-- 4. PROCEDIMIENTO DE REFRESCO ASÍNCRONO Y EXPORTACIÓN LIMPIA
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
