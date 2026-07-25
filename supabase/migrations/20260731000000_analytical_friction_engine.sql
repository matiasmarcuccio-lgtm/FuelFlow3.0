CREATE OR REPLACE FUNCTION public.get_fleet_friction_metrics(p_fleet_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_assets INT;
    v_assets_in_maintenance INT;
    v_total_cash_burn NUMERIC;
    v_fatigued_operators INT;
    v_result JSONB;
BEGIN
    -- 1. Estado de la Flota
    SELECT count(*) INTO v_total_assets FROM public.assets WHERE fleet_id = p_fleet_id;
    SELECT count(*) INTO v_assets_in_maintenance FROM public.assets WHERE fleet_id = p_fleet_id AND status = 'maintenance';

    -- 2. Quema de Efectivo Diaria (Máquinas asignadas pero no facturando / estancadas en pending_prestart)
    -- Calculamos el lucro cesante asumiendo que un camión en pending_prestart pierde el hourly_rate_asset
    SELECT COALESCE(SUM(
        EXTRACT(EPOCH FROM (now() - aa.created_at)) / 3600.0 * bc.hourly_rate_asset
    ), 0) INTO v_total_cash_burn
    FROM public.asset_assignments aa
    JOIN public.assets a ON aa.asset_id = a.id
    JOIN public.billing_contracts bc ON a.id = bc.asset_id
    WHERE a.fleet_id = p_fleet_id 
      AND aa.status = 'pending_prestart'
      AND bc.is_active = true
      AND aa.created_at >= current_date;

    -- 3. Densidad de Fatiga WHS (Operadores al borde del límite de 10h)
    SELECT count(DISTINCT driver_id) INTO v_fatigued_operators
    FROM public.asset_assignments aa
    JOIN public.assets a ON aa.asset_id = a.id
    WHERE a.fleet_id = p_fleet_id
      AND aa.created_at >= current_date
      AND (EXTRACT(EPOCH FROM (COALESCE(aa.shift_end, now()) - aa.created_at)) / 3600.0) >= 10.0;

    v_result := jsonb_build_object(
        'fleet_readiness_percent', CASE WHEN v_total_assets > 0 THEN ROUND(((v_total_assets - v_assets_in_maintenance)::numeric / v_total_assets) * 100, 1) ELSE 0 END,
        'active_maintenance_locks', v_assets_in_maintenance,
        'daily_idle_cash_burn_aud', ROUND(v_total_cash_burn, 2),
        'critical_fatigue_operators', v_fatigued_operators,
        'timestamp', now()
    );

    RETURN v_result;
END;
$$;
