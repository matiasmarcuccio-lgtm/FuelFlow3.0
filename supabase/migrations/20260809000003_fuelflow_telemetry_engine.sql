-- 1. INYECTAR LÍNEA BASE DE CONSUMO OEM EN MAQUINARIA (Si no existía)
-- Ej: Una excavadora CAT 320 o un camión articulado quema aprox. 35.00 L/Hora en trabajo duro.
ALTER TABLE public.assets ADD COLUMN IF NOT EXISTS baseline_burn_rate_lph NUMERIC(5,2) DEFAULT 35.00;
ALTER TABLE public.assets ADD COLUMN IF NOT EXISTS current_engine_hours NUMERIC(8,1) DEFAULT 0.0;

-- 2. TABLA INMUTABLE DE TELEMETRÍA DE COMBUSTIBLE (WORM)
CREATE TABLE IF NOT EXISTS public.fuel_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fleet_id UUID NOT NULL,
    asset_id UUID NOT NULL REFERENCES public.assets(id),
    operator_uid UUID NOT NULL REFERENCES auth.users(id),
    shift_id UUID REFERENCES public.shift_logs(id),
    liters_filled NUMERIC(6,2) NOT NULL CHECK (liters_filled > 0),
    cost_per_liter NUMERIC(5,2) NOT NULL DEFAULT 1.85, -- Precio base diésel minero tasmano
    total_cost NUMERIC(8,2) NOT NULL,
    engine_hours_at_fill NUMERIC(8,1) NOT NULL,
    previous_engine_hours NUMERIC(8,1) NOT NULL,
    hours_elapsed NUMERIC(6,1) NOT NULL,
    burn_rate_lph NUMERIC(6,2) NOT NULL, -- Litros quemados por hora-motor
    haul_cycles_since_last_fill INT NOT NULL DEFAULT 0,
    tonnage_moved_since_last_fill NUMERIC(8,2) NOT NULL DEFAULT 0.00,
    status VARCHAR(30) NOT NULL CHECK (status IN ('VERIFIED', 'ANOMALY_HIGH_BURN', 'ANOMALY_IDLE_BURN', 'THEFT_SUSPECTED')),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Escudo WORM: Nadie puede alterar los registros de repostaje una vez firmados
REVOKE DELETE, UPDATE ON public.fuel_logs FROM authenticated, anon;

-- 3. EL PROCEDIMIENTO ATÓMICO DE TRIANGULACIÓN Y ALERTA (CAPA 0)
CREATE OR REPLACE FUNCTION public.fn_submit_fuel_log(
    p_asset_id UUID,
    p_liters_filled NUMERIC(6,2),
    p_engine_hours NUMERIC(8,1),
    p_cost_per_liter NUMERIC(5,2) DEFAULT 1.85,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_uid UUID;
    v_profile RECORD;
    v_asset RECORD;
    v_last_fill RECORD;
    v_active_shift UUID;
    v_hours_elapsed NUMERIC(6,1);
    v_burn_rate NUMERIC(6,2);
    v_cycles_count INT := 0;
    v_tonnage_sum NUMERIC(8,2) := 0.00;
    v_status VARCHAR(30) := 'VERIFIED';
    v_now TIMESTAMPTZ := now();
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Terminal carece de sesión AAL2 válida.' USING ERRCODE = '40100';
    END IF;

    SELECT fleet_id, role INTO v_profile FROM public.profiles WHERE id = v_caller_uid;
    IF NOT FOUND OR v_profile.fleet_id IS NULL THEN
        RAISE EXCEPTION 'JURISDICTION_MISSING: Operario no vinculado a una flota.' USING ERRCODE = '42501';
    END IF;

    -- Bloqueo pesimista del activo para evitar recargas concurrentes (Double-Billing)
    SELECT id, fleet_id, baseline_burn_rate_lph, current_engine_hours 
    INTO v_asset FROM public.assets WHERE id = p_asset_id FOR UPDATE;

    IF NOT FOUND OR v_asset.fleet_id != v_profile.fleet_id THEN
        RAISE EXCEPTION 'ASSET_VIOLATION: Maquinaria ajena a su jurisdicción.' USING ERRCODE = '42501';
    END IF;

    -- ADUANA DE FÍSICA TEMPORAL: El horómetro nuevo NUNCA puede ser menor al actual
    IF p_engine_hours < v_asset.current_engine_hours THEN
        RAISE EXCEPTION 'ODOMETER_TAMPERING: Las horas-motor introducidas (%.1f) son inferiores al último registro oficial del servidor (%.1f).', p_engine_hours, v_asset.current_engine_hours
            USING ERRCODE = '22023';
    END IF;

    -- Extraer el último repostaje para calcular el delta temporal
    SELECT engine_hours_at_fill, created_at INTO v_last_fill 
    FROM public.fuel_logs WHERE asset_id = p_asset_id ORDER BY created_at DESC LIMIT 1;

    IF FOUND THEN
        v_hours_elapsed := p_engine_hours - v_last_fill.engine_hours_at_fill;
        
        -- TRIANGULACIÓN CON CONDUCTO 2: ¿Cuántos viajes y toneladas movió desde la última recarga?
        SELECT COUNT(*), COALESCE(SUM(tonnage_moved), 0.00)
        INTO v_cycles_count, v_tonnage_sum
        FROM public.haul_cycles
        WHERE asset_id = p_asset_id 
          AND state = 'COMPLETED' 
          AND completed_at >= v_last_fill.created_at;
    ELSE
        -- Primer repostaje registrado en la historia del camión dentro de JITSite
        v_hours_elapsed := GREATEST(1.0, p_engine_hours - v_asset.current_engine_hours);
    END IF;

    -- Evitar división por cero si recargan dos veces seguidas con el motor apagado
    IF v_hours_elapsed <= 0 THEN
        v_burn_rate := p_liters_filled; -- Tasa punitiva artificial para disparar anomalía
    ELSE
        v_burn_rate := p_liters_filled / v_hours_elapsed;
    END IF;

    -- =========================================================================
    -- MOTOR ALGORÍTMICO DE DETECCIÓN DE ANOMALÍAS Y ROBO EN TERRENO
    -- =========================================================================
    
    -- REGLA A: Sospecha de sifón / robo (Cargó más de 50L pero el motor no sumó horas o no hizo viajes)
    IF v_hours_elapsed <= 0.2 AND p_liters_filled > 50.00 THEN
        v_status := 'THEFT_SUSPECTED';
    
    -- REGLA B: Consumo excesivo / fuga grave (Quema 25% más del límite OEM del fabricante)
    ELSIF v_burn_rate > (v_asset.baseline_burn_rate_lph * 1.25) THEN
        v_status := 'ANOMALY_HIGH_BURN';
        
    -- REGLA C: Ralentí abusivo (Sumó más de 3 horas motor quemando combustible pero movió 0 toneladas)
    ELSIF v_hours_elapsed >= 3.0 AND v_tonnage_sum = 0.00 AND p_liters_filled > 40.00 THEN
        v_status := 'ANOMALY_IDLE_BURN';
    END IF;

    -- Identificar si hay un turno activo en esa cabina
    SELECT id INTO v_active_shift FROM public.shift_logs 
    WHERE operator_uid = v_caller_uid AND status = 'ACTIVE' ORDER BY started_at DESC LIMIT 1;

    -- TRANSACCIÓN ATÓMICA A: Insertar en el libro mayor de combustible
    INSERT INTO public.fuel_logs (
        fleet_id, asset_id, operator_uid, shift_id,
        liters_filled, cost_per_liter, total_cost,
        engine_hours_at_fill, previous_engine_hours, hours_elapsed,
        burn_rate_lph, haul_cycles_since_last_fill, tonnage_moved_since_last_fill,
        status, notes
    ) VALUES (
        v_profile.fleet_id, p_asset_id, v_caller_uid, v_active_shift,
        p_liters_filled, p_cost_per_liter, (p_liters_filled * p_cost_per_liter),
        p_engine_hours, COALESCE(v_last_fill.engine_hours_at_fill, v_asset.current_engine_hours), v_hours_elapsed,
        v_burn_rate, v_cycles_count, v_tonnage_sum,
        v_status, UPPER(trim(p_notes))
    );

    -- TRANSACCIÓN ATÓMICA B: Actualizar el horómetro maestro en el activo
    UPDATE public.assets SET current_engine_hours = p_engine_hours, updated_at = v_now WHERE id = p_asset_id;

    -- TRANSACCIÓN ATÓMICA C: Si hay anomalía forense, disparar sirena en el libro de mantenimiento
    IF v_status != 'VERIFIED' THEN
        INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
        VALUES (
            p_asset_id,
            '🚨 ALERTA FUELFLOW [' || v_status || ']: INYECTADOS ' || p_liters_filled || 'L. TASA: ' || ROUND(v_burn_rate, 1) || ' L/H (OEM: ' || v_asset.baseline_burn_rate_lph || ' L/H). TRABAJO: ' || v_tonnage_sum || 't EN ' || v_cycles_count || ' VIAJES.',
            v_caller_uid,
            'open'
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'status', v_status,
        'liters_filled', p_liters_filled,
        'total_cost', (p_liters_filled * p_cost_per_liter),
        'burn_rate_lph', ROUND(v_burn_rate, 2),
        'hours_elapsed', v_hours_elapsed,
        'tonnage_cross_ref', v_tonnage_sum,
        'timestamp', v_now
    );
END;
$$;
