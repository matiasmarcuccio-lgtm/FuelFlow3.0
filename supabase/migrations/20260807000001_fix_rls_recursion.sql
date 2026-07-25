-- Función para saltarse el RLS y obtener la flota del usuario
CREATE OR REPLACE FUNCTION public.get_auth_user_fleet_id()
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT fleet_id FROM public.profiles WHERE id = auth.uid();
$$;

-- Función para saltarse el RLS y obtener el rol del usuario
CREATE OR REPLACE FUNCTION public.get_auth_user_role()
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT role::text FROM public.profiles WHERE id = auth.uid();
$$;

-- Borrar la política defectuosa
DROP POLICY IF EXISTS "RLS_Profiles_Read_Jurisdiction" ON public.profiles;

-- Crear política sin recursión
CREATE POLICY "RLS_Profiles_Read_Jurisdiction" ON public.profiles
FOR SELECT TO authenticated
USING (
    auth.uid() = id
    OR
    (
        public.get_auth_user_role() IN ('supervisor', 'fleet_manager', 'super_admin')
        AND fleet_id = public.get_auth_user_fleet_id()
    )
    OR
    public.get_auth_user_role() = 'super_admin'
);
