-- 1. Inyección del nuevo estado lógico
ALTER TYPE public.assignment_status ADD VALUE IF NOT EXISTS 'revoked';

-- 2. RPC de Revocación Táctica
CREATE OR REPLACE FUNCTION public.revoke_pending_shift(p_assignment_id UUID, p_reason TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_role TEXT;
    v_status assignment_status;
BEGIN
    v_caller_id := auth.uid();
    -- Obtenemos el rol desde profiles
    SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id;

    IF v_caller_role NOT IN ('supervisor', 'fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_UNAUTHORIZED: Solo el mando logístico puede revocar un despacho.';
    END IF;

    -- Bloqueo y verificación
    SELECT status INTO v_status 
    FROM public.asset_assignments 
    WHERE id = p_assignment_id FOR UPDATE;

    IF v_status != 'pending_prestart' THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_CONFLICT: Solo se pueden revocar turnos que nunca iniciaron la operación física.';
    END IF;

    -- Aniquilación del turno: Colapsamos el tiempo y estampamos la auditoría
    UPDATE public.asset_assignments
    SET 
        status = 'revoked',
        shift_end = now(),
        fatigue_override_reason = '[REVOKED ABANDONMENT] ' || COALESCE(p_reason, ''),
        override_approved_by = v_caller_id
    WHERE id = p_assignment_id;
END;
$$;

-- 3. Actualizar la función de validación de despacho para excluir turnos revocados
CREATE OR REPLACE FUNCTION public.trg_validate_dispatch()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_req_license UUID;
    v_has_license BOOLEAN;
    v_total_hours NUMERIC;
    v_asset_status asset_status;
BEGIN
    -- A. Validar que el activo existe y está operativo
    SELECT required_license_id, status INTO v_req_license, v_asset_status
    FROM public.assets
    WHERE id = NEW.asset_id;

    IF v_asset_status != 'operational' THEN
        RAISE EXCEPTION 'WHS_ASSET_NOT_OPERATIONAL: Cannot assign an asset in % state.', v_asset_status;
    END IF;

    -- B. Validar Licencia del Conductor en tiempo real
    SELECT EXISTS (
        SELECT 1 FROM public.driver_licenses
        WHERE driver_id = NEW.driver_id
          AND license_category_id = v_req_license
          AND expiry_date >= CURRENT_DATE
    ) INTO v_has_license;

    IF NOT v_has_license THEN
        RAISE EXCEPTION 'WHS_INVALID_LICENSE: Driver lacks a valid unexpired license for this asset category.';
    END IF;

    -- C. Validación Dinámica de Fatiga (El Muro Permeable)
    -- Sumamos las horas de todos los turnos en las últimas 24 horas para este conductor
    SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (COALESCE(shift_end, now()) - shift_start)) / 3600), 0)
    INTO v_total_hours
    FROM public.asset_assignments
    WHERE driver_id = NEW.driver_id
      AND shift_start >= now() - INTERVAL '24 hours'
      AND status != 'revoked' -- NO CONTAR TURNOS REVOCADOS
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

    -- Límite WHS: 12 horas acumuladas.
    IF v_total_hours >= 12 THEN
        -- Si no hay justificación escrita, se aborta irrevocablemente la transacción
        IF NEW.fatigue_override_reason IS NULL OR TRIM(NEW.fatigue_override_reason) = '' THEN
            RAISE EXCEPTION 'WHS_FATIGUE_LIMIT: Driver accumulated % hours in 24h (>12h). Auditable override reason required.', ROUND(v_total_hours, 1);
        END IF;
        
        -- Si hay justificación, forzamos que quede sellada por quien aprueba
        IF NEW.override_approved_by IS NULL THEN
            NEW.override_approved_by := NEW.assigned_by;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;
