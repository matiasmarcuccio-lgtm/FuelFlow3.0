-- El Procedimiento de Liberación Criptográfica
CREATE OR REPLACE FUNCTION public.release_asset_from_maintenance(
    p_asset_id UUID,
    p_release_notes TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_mechanic_uid UUID;
    v_log_id UUID;
    v_actor_role TEXT;
BEGIN
    v_mechanic_uid := auth.uid();
    v_actor_role := current_setting('request.jwt.claims', true)::jsonb ->> 'user_role';

    -- Fricción Forense 1: Solo personal de taller o super_admin puede liberar
    IF v_actor_role NOT IN ('fitter', 'fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'WHS_UNAUTHORIZED: Solo el personal certificado de taller puede firmar la liberación de un activo.';
    END IF;
    
    -- Fricción Forense 2: Justificación legal obligatoria
    IF length(trim(p_release_notes)) < 15 THEN
        RAISE EXCEPTION 'WHS_INVALID_RELEASE: Se requiere un informe pericial de reparación de al menos 15 caracteres.';
    END IF;

    -- Buscar el secuestro activo
    SELECT id INTO v_log_id
    FROM public.maintenance_logs
    WHERE asset_id = p_asset_id AND status = 'open'
    ORDER BY created_at DESC LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_VIOLATION: Este activo no posee bloqueos mecánicos activos.';
    END IF;

    -- Transacción Atómica: Cierre de bitácora y liberación del activo
    UPDATE public.maintenance_logs
    SET status = 'resolved',
        released_by_uid = v_mechanic_uid,
        resolution_notes = p_release_notes,
        released_at = now()
    WHERE id = v_log_id;

    UPDATE public.assets
    SET status = 'available'
    WHERE id = p_asset_id;
END;
$$;
