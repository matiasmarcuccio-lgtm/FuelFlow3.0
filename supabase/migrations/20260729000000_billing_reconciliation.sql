-- 1. Ampliación del Libro Mayor Financiero
ALTER TABLE public.execution_certificates
ADD COLUMN telemetry_source VARCHAR(50) NOT NULL DEFAULT 'tablet_gps_time',
ADD COLUMN telemetry_confidence NUMERIC(3,2) NOT NULL DEFAULT 0.50, -- 1.00 = IoT CAN Bus, 0.50 = Human/GPS
ADD COLUMN hardware_engine_hours NUMERIC(8,2);

-- 2. Actualización del RPC de Cuantificación (Billing Engine + Telemetry Fallback)
CREATE OR REPLACE FUNCTION public.generate_execution_certificate()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_contract RECORD;
    v_total_hours NUMERIC(8, 2);
    v_regular_hours NUMERIC(8, 2);
    v_overtime_hours NUMERIC(8, 2);
    v_asset_subtotal NUMERIC(12, 2);
    v_operator_subtotal NUMERIC(12, 2);
    
    -- Variables de telemetría IoT
    v_start_engine_hours NUMERIC(10, 2);
    v_end_engine_hours NUMERIC(10, 2);
    v_iot_delta_hours NUMERIC(8, 2);
    
    -- Metadatos de confianza
    v_source VARCHAR(50) := 'tablet_gps_time';
    v_confidence NUMERIC(3, 2) := 0.50;
BEGIN
    IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        
        SELECT * INTO v_contract 
        FROM public.billing_contracts 
        WHERE asset_id = NEW.asset_id AND is_active = true;
        
        IF NOT FOUND THEN
            RETURN NEW;
        END IF;

        -- 1. Intento de Conciliación IoT (Buscar lectura en el inicio y en el fin)
        SELECT engine_hours INTO v_start_engine_hours 
        FROM public.telemetry_logs 
        WHERE asset_id = NEW.asset_id AND recorded_at >= NEW.prestart_commenced_at 
        ORDER BY recorded_at ASC LIMIT 1;

        SELECT engine_hours INTO v_end_engine_hours 
        FROM public.telemetry_logs 
        WHERE asset_id = NEW.asset_id AND recorded_at <= NEW.shift_end 
        ORDER BY recorded_at DESC LIMIT 1;

        -- 2. Matriz de Fallback (IoT vs Humano)
        IF v_start_engine_hours IS NOT NULL AND v_end_engine_hours IS NOT NULL AND (v_end_engine_hours >= v_start_engine_hours) THEN
            -- Tenemos datos duros del CAN bus. El hardware manda.
            v_iot_delta_hours := v_end_engine_hours - v_start_engine_hours;
            v_total_hours := v_iot_delta_hours;
            v_source := 'iot_can_bus';
            v_confidence := 1.00;
        ELSE
            -- FALLBACK: El activo no tiene hardware IoT o falló la transmisión. 
            -- Se degrada la confianza y se cobra por el tiempo físico del operador.
            v_total_hours := ROUND((EXTRACT(EPOCH FROM (NEW.shift_end - NEW.prestart_commenced_at)) / 3600.0)::numeric, 2);
            v_iot_delta_hours := NULL;
            v_source := 'tablet_gps_time';
            v_confidence := 0.50;
        END IF;

        IF v_total_hours < 0 THEN v_total_hours := 0; END IF;

        -- 3. Cálculo de Fatiga y WHS (Se mantiene idéntico)
        IF v_total_hours > v_contract.overtime_threshold_hours THEN
            v_regular_hours := v_contract.overtime_threshold_hours;
            v_overtime_hours := v_total_hours - v_contract.overtime_threshold_hours;
        ELSE
            v_regular_hours := v_total_hours;
            v_overtime_hours := 0;
        END IF;

        v_asset_subtotal := v_total_hours * v_contract.hourly_rate_asset;

        IF v_contract.model = 'wet_hire' THEN
            v_operator_subtotal := (v_regular_hours * v_contract.hourly_rate_operator) +
                                   (v_overtime_hours * (v_contract.hourly_rate_operator * v_contract.overtime_multiplier));
        ELSE
            v_operator_subtotal := 0;
        END IF;

        -- 4. Inyección en el Libro Mayor con sellos de auditoría
        INSERT INTO public.execution_certificates (
            assignment_id, contract_id, total_hours, regular_hours, overtime_hours,
            asset_subtotal, operator_subtotal, total_billable,
            telemetry_source, telemetry_confidence, hardware_engine_hours
        ) VALUES (
            NEW.id, v_contract.id, v_total_hours, v_regular_hours, v_overtime_hours,
            v_asset_subtotal, v_operator_subtotal, (v_asset_subtotal + v_operator_subtotal),
            v_source, v_confidence, v_iot_delta_hours
        );
        
    END IF;
    RETURN NEW;
END;
$$;
