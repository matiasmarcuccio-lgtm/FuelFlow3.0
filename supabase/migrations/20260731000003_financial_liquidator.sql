-- Liquidador Financiero: Cierre de Turno y Certificación Forense

CREATE OR REPLACE FUNCTION public.close_active_shift(p_assignment_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_shift RECORD;
    v_contract RECORD;
    v_hours_worked NUMERIC;
    v_billable_amount NUMERIC;
    v_certificate_id UUID;
BEGIN
    -- 1. Validar jurisdicción y estado
    SELECT * INTO v_shift FROM public.asset_assignments 
    WHERE id = p_assignment_id AND driver_id = auth.uid() AND status = 'in_progress'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_VIOLATION: No hay un turno en progreso válido para cerrar bajo tu jurisdicción.';
    END IF;

    -- 2. Obtener el contrato comercial asociado a la máquina
    SELECT * INTO v_contract FROM public.billing_contracts 
    WHERE asset_id = v_shift.asset_id AND is_active = true LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'BILLING_ERROR: Activo sin contrato de facturación activo. Imposible liquidar.';
    END IF;

    -- 3. Calcular la termodinámica financiera
    v_hours_worked := EXTRACT(EPOCH FROM (now() - v_shift.created_at)) / 3600.0;
    
    -- Lógica base: Si supera el umbral de horas extra, aplicar multiplicador
    IF v_hours_worked > v_contract.overtime_threshold_hours THEN
        v_billable_amount := (v_contract.overtime_threshold_hours * v_contract.hourly_rate_asset) + 
                             ((v_hours_worked - v_contract.overtime_threshold_hours) * (v_contract.hourly_rate_asset * v_contract.overtime_multiplier));
    ELSE
        v_billable_amount := v_hours_worked * v_contract.hourly_rate_asset;
    END IF;

    -- 4. Cerrar el turno y generar el certificado forense
    UPDATE public.asset_assignments 
    SET status = 'completed', shift_end = now() 
    WHERE id = p_assignment_id;

    INSERT INTO public.execution_certificates (
        asset_assignment_id, total_hours, total_billable, telemetry_confidence, telemetry_source
    ) VALUES (
        p_assignment_id, ROUND(v_hours_worked, 2), ROUND(v_billable_amount, 2), 'high', 'human_kiosk'
    ) RETURNING id INTO v_certificate_id;

    RETURN jsonb_build_object('success', true, 'certificate_id', v_certificate_id, 'billable_amount', v_billable_amount);
END;
$$;
