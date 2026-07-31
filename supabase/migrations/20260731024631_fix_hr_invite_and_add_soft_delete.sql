-- 1. Arreglar la generación de invitaciones para que el Dueño (account_owner) tenga permiso
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

-- 2. Función para dar de baja a un usuario (Soft Delete / Inactivar) en vez de destruirlo
CREATE OR REPLACE FUNCTION public.fn_disable_crew_member(p_profile_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_caller_role VARCHAR(50);
    v_caller_fleet UUID;
    v_target_fleet UUID;
BEGIN
    SELECT role, fleet_id INTO v_caller_role, v_caller_fleet
    FROM public.profiles WHERE id = auth.uid();
    
    IF v_caller_role NOT IN ('account_owner', 'fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE: Solo la gerencia puede dar de baja al personal.';
    END IF;

    SELECT fleet_id INTO v_target_fleet FROM public.profiles WHERE id = p_profile_id;
    IF v_target_fleet != v_caller_fleet THEN
        RAISE EXCEPTION 'CROSS_FLEET_VIOLATION: No puede alterar personal de otra jurisdicción.';
    END IF;

    -- Soft Delete: Cambiar estado a INACTIVE. Se conservan todos los registros históricos.
    UPDATE public.profiles SET status = 'INACTIVE' WHERE id = p_profile_id;

    RETURN true;
END;
$$;

-- 3. Función para revocar (destruir) una invitación que aún no ha sido usada
CREATE OR REPLACE FUNCTION public.fn_revoke_fleet_invite(p_token VARCHAR)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_caller_role VARCHAR(50);
    v_caller_fleet UUID;
BEGIN
    SELECT role, fleet_id INTO v_caller_role, v_caller_fleet
    FROM public.profiles WHERE id = auth.uid();
    
    IF v_caller_role NOT IN ('account_owner', 'fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE';
    END IF;

    DELETE FROM public.fleet_invites 
    WHERE token = p_token AND fleet_id = v_caller_fleet;

    RETURN true;
END;
$$;
