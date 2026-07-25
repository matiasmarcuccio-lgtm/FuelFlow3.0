CREATE OR REPLACE FUNCTION public.fn_consume_fleet_invite(
    p_token VARCHAR(10)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_invite RECORD;
    v_caller_uid UUID;
BEGIN
    v_caller_uid := auth.uid();
    
    -- ADUANA 0: Verificar identidad básica en el motor
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '40100';
    END IF;

    -- ADUANA 1: Bloqueo transaccional FOR UPDATE contra Double-Spending
    SELECT id, fleet_id, role, expires_at, consumed_at
    INTO v_invite
    FROM public.fleet_invites
    WHERE token = UPPER(TRIM(p_token))
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TOKEN_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;

    IF v_invite.consumed_at IS NOT NULL THEN
        RAISE EXCEPTION 'TOKEN_ALREADY_CONSUMED' USING ERRCODE = '40900';
    END IF;

    IF v_invite.expires_at < now() THEN
        RAISE EXCEPTION 'TOKEN_EXPIRED' USING ERRCODE = '41000';
    END IF;

    -- TRANSACCIÓN ATÓMICA A: Quemar el token permanentemente
    UPDATE public.fleet_invites
    SET consumed_at = now(),
        consumed_by_uid = v_caller_uid
    WHERE id = v_invite.id;

    -- TRANSACCIÓN ATÓMICA B: Vincular la jurisdicción y el rol en la tabla pública de perfiles
    UPDATE public.profiles
    SET fleet_id = v_invite.fleet_id,
        role = LOWER(v_invite.role),
        updated_at = now()
    WHERE id = v_caller_uid;

    -- Fallback Defensivo
    IF NOT FOUND THEN
        INSERT INTO public.profiles (id, full_name, role, fleet_id, created_at, updated_at)
        VALUES (
            v_caller_uid, 
            'terminal_' || substr(v_caller_uid::text, 1, 8) || '@jitsite.device', 
            LOWER(v_invite.role), 
            v_invite.fleet_id, 
            now(), 
            now()
        );
    END IF;

    -- TRANSACCIÓN ATÓMICA C: Registro inmutable en el libro mayor de auditoría
    INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
    VALUES (
        NULL,
        'TERMINAL VINCULADA VÍA TOKEN ' || UPPER(TRIM(p_token)),
        v_caller_uid,
        'closed'
    );

    RETURN jsonb_build_object(
        'success', true,
        'fleet_id', v_invite.fleet_id,
        'assigned_role', LOWER(v_invite.role),
        'operator_uid', v_caller_uid,
        'timestamp', now()
    );
END;
$$;
