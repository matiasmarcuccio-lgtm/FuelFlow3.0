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
