-- 1. Crear la función del Auth Hook
CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    claims jsonb;
    user_role text;
    user_fleet_id uuid;
    fleet_status text;
BEGIN
    claims := event->'claims';
    
    SELECT p.role, p.fleet_id, f.status 
    INTO user_role, user_fleet_id, fleet_status
    FROM public.profiles p
    LEFT JOIN public.fleets f ON p.fleet_id = f.id
    WHERE p.id = (event->>'user_id')::uuid;

    IF user_role IS NOT NULL THEN
        claims := jsonb_set(claims, '{user_role}', to_jsonb(user_role));
        claims := jsonb_set(claims, '{fleet_id}', to_jsonb(user_fleet_id));
        claims := jsonb_set(claims, '{subscription_status}', to_jsonb(fleet_status));
    END IF;

    event := jsonb_set(event, '{claims}', claims);
    RETURN event;
END;
$$;

-- 2. Revocar acceso público y otorgar permisos estrictos al motor de Auth
REVOKE ALL ON FUNCTION public.custom_access_token_hook(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) TO supabase_auth_admin;
