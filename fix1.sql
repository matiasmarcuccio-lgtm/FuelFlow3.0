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
