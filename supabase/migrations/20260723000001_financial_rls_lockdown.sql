-- 1. Create the Custom Access Token Hook
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
    -- 1. Extraer los claims actuales
    claims := event->'claims';
    
    -- 2. Buscar el perfil y la flota en una sola consulta
    SELECT p.role, p.fleet_id, f.status 
    INTO user_role, user_fleet_id, fleet_status
    FROM public.profiles p
    LEFT JOIN public.fleets f ON p.fleet_id = f.id
    WHERE p.id = (event->>'user_id')::uuid;

    -- 3. Inyectar la identidad comercial en el JWT
    IF user_role IS NOT NULL THEN
        claims := jsonb_set(claims, '{user_role}', to_jsonb(user_role));
        claims := jsonb_set(claims, '{fleet_id}', to_jsonb(user_fleet_id));
        claims := jsonb_set(claims, '{subscription_status}', to_jsonb(fleet_status));
    END IF;

    -- 4. Retornar el token mutado
    event := jsonb_set(event, '{claims}', claims);
    RETURN event;
END;
$$;

-- 2. Configure Permissions for the Hook
-- Supabase requires the supabase_auth_admin role to execute this hook
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) FROM authenticated, anon, public;

-- 3. Apply the Financial RLS Lockdown (Proof of Concept on 'assets')
DROP POLICY IF EXISTS "asset_fleet_manager_policy" ON "public"."assets";

-- Recreate Policy combining ownership check with Zero-cost memory evaluation of billing status
CREATE POLICY "asset_fleet_manager_policy" ON "public"."assets" FOR ALL 
USING (
    fleet_manager_id = auth.uid()
    AND (current_setting('request.jwt.claims', true)::jsonb ->> 'subscription_status') IN ('active', 'trialing')
);
