CREATE OR REPLACE FUNCTION public.execute_instant_revocation(
    p_target_uid UUID,
    p_forensic_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth -- Autoridad sobre el esquema público y privado de GoTrue
AS $$
DECLARE
    v_actor_role TEXT;
    v_target_email TEXT;
BEGIN
    v_actor_role := LOWER(COALESCE(current_setting('request.jwt.claims', true)::jsonb ->> 'user_role', ''));

    -- Escudo Jurisdiccional: Solo la alta jerarquía puede guillotinar identidades
    IF v_actor_role NOT IN ('fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE: Su JWT (%) carece de soberanía para revocar credenciales operativas.', v_actor_role
            USING ERRCODE = '42501';
    END IF;

    -- Prevenir auto-decapitación accidental o maliciosa
    IF p_target_uid = auth.uid() THEN
        RAISE EXCEPTION 'SUICIDE_PREVENTION: Un operador no puede revocar su propia sesión activa.';
    END IF;

    SELECT email INTO v_target_email FROM auth.users WHERE id = p_target_uid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'TARGET_NOT_FOUND: El UUID proporcionado no existe en el registro biométrico.';
    END IF;

    -- PASO ATÓMICO 1: Bloqueo perpetuo en el núcleo de GoTrue
    UPDATE auth.users
    SET banned_until = '2099-01-01 00:00:00+00'::timestamptz,
        updated_at = now()
    WHERE id = p_target_uid;

    -- PASO ATÓMICO 2: Destrucción física de sesiones y tokens de refresco activos
    DELETE FROM auth.sessions WHERE user_id = p_target_uid;
    DELETE FROM auth.refresh_tokens WHERE user_id = p_target_uid;

    -- PASO ATÓMICO 3: Marcado del perfil público para disparar el evento WebSocket
    UPDATE public.profiles
    SET role = 'revoked',
        fleet_id = NULL,
        updated_at = now()
    WHERE id = p_target_uid;

    -- PASO ATÓMICO 4: Registro forense inmutable (WORM)
    -- Usamos el UUID dummy para asset_id ya que es NOT NULL
    INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
    VALUES (
        '00000000-0000-0000-0000-000000000000', 
        'REVOCACIÓN DE IDENTIDAD APLICADA A: ' || v_target_email || ' (' || p_target_uid || '). RAZÓN: ' || p_forensic_reason, 
        auth.uid(), 
        'resolved'
    );

    RETURN jsonb_build_object(
        'success', true,
        'revoked_uid', p_target_uid,
        'revoked_email', v_target_email,
        'action', 'TERMINATED_AND_PURGED',
        'timestamp', now()
    );
END;
$$;
