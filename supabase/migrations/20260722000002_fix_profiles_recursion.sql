-- 1. Eliminar las políticas defectuosas que causan recursión infinita
DROP POLICY IF EXISTS "HQ_global_select_profiles" ON profiles;
DROP POLICY IF EXISTS "HQ_global_update_profiles" ON profiles;

-- 2. Crear una función SECURITY DEFINER para leer el rol aislando el contexto de RLS
CREATE OR REPLACE FUNCTION public.get_auth_user_role()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM profiles WHERE id = auth.uid();
$$;

-- 3. Recrear las políticas utilizando la función segura
CREATE POLICY "HQ_global_select_profiles" ON profiles
    FOR SELECT USING (
        public.get_auth_user_role() IN ('super_admin', 'fleet_manager')
    );

CREATE POLICY "HQ_global_update_profiles" ON profiles
    FOR UPDATE USING (
        public.get_auth_user_role() IN ('super_admin', 'fleet_manager')
    );
