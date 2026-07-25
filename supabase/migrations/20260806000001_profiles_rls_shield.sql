-- 1. LIMPIEZA DE POLÍTICAS INGENUAS PREVIAS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Fleet managers can view team profiles" ON public.profiles;

-- 2. ESCUDO 1: PRIVILEGIOS DE COLUMNA (La verdadera barrera física)
REVOKE ALL ON public.profiles FROM authenticated;
REVOKE ALL ON public.profiles FROM anon;

GRANT SELECT ON public.profiles TO authenticated;

-- GRANT adaptado a las columnas reales del sistema actual.
GRANT UPDATE (full_name, updated_at) ON public.profiles TO authenticated;

-- 3. ESCUDO 2: POLÍTICAS RLS DE LECTURA Y ESCRITURA
CREATE POLICY "RLS_Profiles_Read_Jurisdiction" ON public.profiles
FOR SELECT TO authenticated
USING (
    auth.uid() = id
    OR
    (
        EXISTS (
            SELECT 1 FROM public.profiles as viewer
            WHERE viewer.id = auth.uid()
            AND viewer.role IN ('supervisor', 'fleet_manager', 'super_admin')
            AND viewer.fleet_id = public.profiles.fleet_id
        )
    )
    OR
    (
        EXISTS (
            SELECT 1 FROM public.profiles as admin
            WHERE admin.id = auth.uid() AND admin.role = 'super_admin'
        )
    )
);

CREATE POLICY "RLS_Profiles_Update_Self" ON public.profiles
FOR UPDATE TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- 4. ESCUDO 3: TRIGGER DE GUILLOTINA (Cinturón y Tirantes)
CREATE OR REPLACE FUNCTION public.fn_guard_profile_privileges()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_actor_role TEXT;
BEGIN
    IF (NEW.role IS NOT DISTINCT FROM OLD.role) AND (NEW.fleet_id IS NOT DISTINCT FROM OLD.fleet_id) THEN
        NEW.updated_at := now();
        RETURN NEW;
    END IF;
    IF current_user IN ('postgres', 'supabase_admin', 'service_role') THEN
        NEW.updated_at := now();
        RETURN NEW;
    END IF;

    v_actor_role := LOWER(COALESCE(current_setting('request.jwt.claims', true)::jsonb ->> 'user_role', ''));

    IF v_actor_role != 'super_admin' THEN
        RAISE EXCEPTION 'SECURITY_VIOLATION: Elevación de privilegios denegada. Su JWT (%) carece de soberanía para alterar la columna role o fleet_id.', v_actor_role
            USING ERRCODE = '42501';
    END IF;

    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_profile_privileges ON public.profiles;
CREATE TRIGGER trg_guard_profile_privileges
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.fn_guard_profile_privileges();
