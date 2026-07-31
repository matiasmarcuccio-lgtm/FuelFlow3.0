-- DROP explicitamente las versiones anteriores para evitar colisiones de sobrecarga
DROP FUNCTION IF EXISTS public.fn_generate_fleet_invite(UUID);
DROP FUNCTION IF EXISTS public.fn_generate_fleet_invite(UUID, VARCHAR);

CREATE OR REPLACE FUNCTION public.fn_generate_fleet_invite(p_fleet_id UUID, p_role VARCHAR DEFAULT 'driver')
RETURNS VARCHAR(10)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_token VARCHAR(10);
BEGIN
    -- Verificar si el usuario que llama tiene rol gerencial (incluyendo account_owner)
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role IN ('account_owner', 'fleet_manager', 'super_admin')
    ) THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE: Se requiere ser Gerente o Dueño de Cuenta para generar llaves de abordaje.';
    END IF;

    -- Generar token simple (6 caracteres alfanuméricos en mayúsculas) o UUID
    v_token := UPPER(SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 6));

    INSERT INTO public.fleet_invites (fleet_id, token, created_by, role)
    VALUES (p_fleet_id, v_token, auth.uid(), p_role);

    RETURN v_token;
END;
$$;
