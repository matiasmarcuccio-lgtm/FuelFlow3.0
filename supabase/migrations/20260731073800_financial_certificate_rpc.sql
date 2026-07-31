BEGIN;

-- Add fleet_id to execution_certificates if it does not exist to support the new billing schema
ALTER TABLE public.execution_certificates
ADD COLUMN IF NOT EXISTS fleet_id UUID;

-- Agregar la llave foránea al turno si no existe
ALTER TABLE public.asset_assignments 
ADD COLUMN IF NOT EXISTS certificate_id UUID REFERENCES public.execution_certificates(id);

CREATE OR REPLACE FUNCTION public.fn_generate_execution_certificate(
    p_assignment_ids UUID[],
    p_client_erp_id VARCHAR
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_fleet_id UUID;
    v_client_id UUID;
    v_total_hours NUMERIC := 0;
    v_total_billable NUMERIC := 0;
    v_certificate_id UUID;
    v_assignment RECORD;
    v_hourly_rate NUMERIC := 150.00; -- Tarifa estándar (debería venir del contrato/master_order)
BEGIN
    -- 1. Validar jurisdicción gerencial
    SELECT fleet_id INTO v_fleet_id FROM public.profiles 
    WHERE id = auth.uid() AND role IN ('account_owner', 'super_admin');
    
    IF v_fleet_id IS NULL THEN
        RAISE EXCEPTION 'Violación Financiera: Solo la gerencia puede emitir certificados.';
    END IF;

    -- 2. Validar y bloquear los turnos seleccionados (Prevenir Doble Facturación)
    -- Usamos FOR UPDATE para bloquear las filas durante esta transacción
    FOR v_assignment IN 
        SELECT id, master_order_id, (current_engine_hours) as hours_logged -- Asumiendo cálculo simplificado
        FROM public.asset_assignments 
        WHERE id = ANY(p_assignment_ids) 
          AND status = 'COMPLETED' 
          AND certificate_id IS NULL
          AND fleet_id = v_fleet_id
        FOR UPDATE
    LOOP
        -- Sumar métricas reales aquí (este es un cálculo representativo)
        -- Lo ideal es restar ended_at - created_at o usar telemetría final
        v_total_hours := v_total_hours + 8; -- Placeholder: 8 horas por turno estándar
    END LOOP;

    IF v_total_hours = 0 THEN
        RAISE EXCEPTION 'Error: Ninguno de los turnos seleccionados es válido o ya fueron facturados.';
    END IF;

    v_total_billable := v_total_hours * v_hourly_rate;

    -- 3. Inserción del Certificado (Esto detona tu trigger queue_erp_outbox)
    INSERT INTO public.execution_certificates (fleet_id, billed_to_erp_id, total_hours, total_billable, forensic_pdf_hash)
    VALUES (v_fleet_id, p_client_erp_id, v_total_hours, v_total_billable, 'PENDING_GENERATION')
    RETURNING id INTO v_certificate_id;

    -- 4. Mutación: Marcar turnos como facturados y atarlos al certificado
    UPDATE public.asset_assignments
    SET status = 'BILLED', certificate_id = v_certificate_id
    WHERE id = ANY(p_assignment_ids);

    RETURN v_certificate_id;
END;
$$;

COMMIT;
