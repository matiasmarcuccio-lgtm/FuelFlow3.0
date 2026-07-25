CREATE OR REPLACE FUNCTION public.fn_generate_fleet_invite(p_fleet_id UUID)
RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_token VARCHAR(10);
BEGIN
    -- Verificar si el usuario que llama tiene rol FLEET_MANAGER
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND LOWER(role) IN ('fleet_manager', 'super_admin')
    ) THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE';
    END IF;

    -- Generar token simple (6 caracteres alfanuméricos en mayúsculas)
    v_token := UPPER(SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 6));

    INSERT INTO public.fleet_invites (fleet_id, invite_token, created_by)
    VALUES (p_fleet_id, v_token, auth.uid());

    RETURN v_token;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_revoke_driver_access(p_driver_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_active_loads INT;
BEGIN
    -- Validar permisos del solicitante
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND LOWER(role) IN ('fleet_manager', 'super_admin')
    ) THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE';
    END IF;

    -- Bloqueo Forense: Comprobar si el conductor tiene cargas en tránsito
    SELECT COUNT(id) INTO v_active_loads
    FROM public.load_offers
    WHERE driver_id = p_driver_id 
    AND status IN ('PENDING', 'LOADING', 'IN_TRANSIT', 'AT_WEIGHBRIDGE');

    IF v_active_loads > 0 THEN
        -- El error exacto que la UI debe atrapar
        RAISE EXCEPTION 'ACTIVE_TRANSIT_LOCK';
    END IF;

    -- Ejecutar Baja Definitiva
    UPDATE public.profiles
    SET status = 'INACTIVE'
    WHERE id = p_driver_id;

    RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_override_shift_assignment(p_absent_driver_id UUID, p_reserve_driver_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_shift RECORD;
BEGIN
    -- Validar permisos del solicitante
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND LOWER(role) IN ('fleet_manager', 'super_admin')
    ) THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE';
    END IF;

    -- Obtener el turno activo del conductor ausente
    SELECT * INTO v_current_shift
    FROM public.shift_assignments
    WHERE driver_id = p_absent_driver_id AND status = 'ACTIVE'
    LIMIT 1 FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NO_ACTIVE_SHIFT';
    END IF;

    -- Graceful Shutdown: Cerrar el turno del conductor ausente
    UPDATE public.shift_assignments
    SET 
        status = 'COMPLETED',
        detach_reason = 'SHIFT_OVERRIDE',
        updated_at = NOW()
    WHERE id = v_current_shift.id;

    -- Iniciar el nuevo turno para el conductor de reserva heredando vehículo y orden maestra
    INSERT INTO public.shift_assignments (
        fleet_id,
        driver_id,
        vehicle_id,
        master_order_id,
        status,
        intent_to_detach
    ) VALUES (
        v_current_shift.fleet_id,
        p_reserve_driver_id,
        v_current_shift.vehicle_id,
        v_current_shift.master_order_id,
        'ACTIVE',
        false
    );

    RETURN true;
END;
$$;
