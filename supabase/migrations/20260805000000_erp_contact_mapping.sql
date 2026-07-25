-- 1. Inyectar el identificador del ERP en los contratos de facturación
ALTER TABLE public.billing_contracts
ADD COLUMN IF NOT EXISTS erp_contact_id VARCHAR(255);

-- Opcional: Un índice para acelerar búsquedas de auditoría por cliente del ERP
CREATE INDEX IF NOT EXISTS idx_billing_contracts_erp_contact ON public.billing_contracts(erp_contact_id);

-- 2. Inyectar el campo de destino en el certificado inmutable para preservar la cadena de custodia
ALTER TABLE public.execution_certificates
ADD COLUMN IF NOT EXISTS billed_to_erp_id VARCHAR(255);

-- 3. Actualizar el Liquidador Financiero
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

    -- 2. Obtener el contrato comercial asociado
    SELECT * INTO v_contract FROM public.billing_contracts 
    WHERE asset_id = v_shift.asset_id AND is_active = true LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'BILLING_ERROR: Activo sin contrato de facturación activo. Imposible liquidar.';
    END IF;

    -- 3. ESCUDO DE ENRUTAMIENTO ERP (La Nueva Frontera)
    IF v_contract.erp_contact_id IS NULL OR length(v_contract.erp_contact_id) < 2 THEN
        RAISE EXCEPTION 'ERP_MAPPING_MISSING: El contrato comercial no está vinculado a un cliente en Xero/SAP. El turno no puede cerrarse hasta que administración asigne un erp_contact_id.';
    END IF;

    -- 4. Calcular la termodinámica financiera
    v_hours_worked := EXTRACT(EPOCH FROM (now() - v_shift.created_at)) / 3600.0;
    
    IF v_hours_worked > v_contract.overtime_threshold_hours THEN
        v_billable_amount := (v_contract.overtime_threshold_hours * v_contract.hourly_rate_asset) + 
                             ((v_hours_worked - v_contract.overtime_threshold_hours) * (v_contract.hourly_rate_asset * v_contract.overtime_multiplier));
    ELSE
        v_billable_amount := v_hours_worked * v_contract.hourly_rate_asset;
    END IF;

    -- 5. Cerrar el turno y generar el certificado forense, sellando el ID del cliente
    UPDATE public.asset_assignments 
    SET status = 'completed', shift_end = now() 
    WHERE id = p_assignment_id;

    INSERT INTO public.execution_certificates (
        asset_assignment_id, total_hours, total_billable, telemetry_confidence, telemetry_source, billed_to_erp_id
    ) VALUES (
        p_assignment_id, ROUND(v_hours_worked, 2), ROUND(v_billable_amount, 2), 'high', 'human_kiosk', v_contract.erp_contact_id
    ) RETURNING id INTO v_certificate_id;

    RETURN jsonb_build_object('success', true, 'certificate_id', v_certificate_id, 'billable_amount', v_billable_amount);
END;
$$;

-- 4. Actualización del Outbox Trigger
CREATE OR REPLACE FUNCTION public.queue_erp_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.erp_outbox (certificate_id, payload)
    VALUES (
        NEW.id,
        jsonb_build_object(
            'event', 'billing.certificate.generated',
            'certificate_id', NEW.id,
            'total_billable', NEW.total_billable,
            'total_hours', NEW.total_hours,
            'forensic_hash', NEW.forensic_pdf_hash,
            'client_xero_id', NEW.billed_to_erp_id, -- INYECCIÓN DIRECTA PARA N8N
            'timestamp', now()
        )
    );
    RETURN NEW;
END;
$$;
