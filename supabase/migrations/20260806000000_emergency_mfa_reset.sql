CREATE OR REPLACE FUNCTION public.emergency_reset_mfa(p_target_uid UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_actor_role TEXT;
BEGIN
    v_actor_role := current_setting('request.jwt.claims', true)::jsonb ->> 'user_role';

    -- Fricción Absoluta: Solo la máxima autoridad puede ejecutar esto
    IF v_actor_role != 'super_admin' THEN
        RAISE EXCEPTION 'CRITICAL: Solo un super administrador puede ejecutar el protocolo de rescate biométrico.';
    END IF;

    -- Eliminar todos los factores de autenticación del usuario objetivo en el núcleo de Supabase
    DELETE FROM auth.mfa_factors WHERE user_id = p_target_uid;
    DELETE FROM auth.mfa_amr_claims WHERE session_id IN (SELECT id FROM auth.sessions WHERE user_id = p_target_uid);
    
    -- Insertar huella forense inmutable de la acción
    INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
    VALUES (NULL, 'RESETEO MFA DE EMERGENCIA APLICADO AL UID: ' || p_target_uid, auth.uid(), 'closed');
END;
$$;
