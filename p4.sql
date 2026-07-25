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
