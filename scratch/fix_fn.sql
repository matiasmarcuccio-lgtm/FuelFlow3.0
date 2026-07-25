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
