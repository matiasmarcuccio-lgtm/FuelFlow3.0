-- 1. Asegurar limpieza de la función previa
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user_registration();

-- 2. Forjar el procedimiento de registro atómico y blindado
CREATE OR REPLACE FUNCTION public.handle_new_user_registration()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public -- Previene ataques de secuestro de esquema (Schema Injection)
AS $$
DECLARE
    v_raw_role TEXT;
    v_clean_role TEXT;
    v_raw_fleet UUID;
BEGIN
    -- Extracción y sanitización forense de metadatos entrantes
    v_raw_role := COALESCE(new.raw_user_meta_data->>'role', 'driver');
    v_clean_role := LOWER(TRIM(v_raw_role));

    -- Validación estricta contra la lista blanca de jurisdicciones
    IF v_clean_role NOT IN ('driver', 'fitter', 'supervisor', 'fleet_manager', 'super_admin') THEN
        v_clean_role := 'driver'; -- Degradación segura por defecto si el rol es inválido
    END IF;

    -- Captura preventiva de UUID vacío ("") para evitar error de sintaxis en Foreign Key
    IF (new.raw_user_meta_data->>'fleet_id') IS NULL OR TRIM(new.raw_user_meta_data->>'fleet_id') = '' THEN
        -- Como fleet_id es NOT NULL en profiles, auto-creamos una flota si es fleet_manager
        IF v_clean_role = 'fleet_manager' THEN
            INSERT INTO public.fleets (name, status, tier)
            VALUES ('Flota de ' || new.email, 'past_due', 'basic')
            RETURNING id INTO v_raw_fleet;
        ELSE
            -- Fallback si no es manager y no tiene flota
            v_raw_fleet := '00000000-0000-0000-0000-000000000000'::UUID;
        END IF;
    ELSE
        BEGIN
            v_raw_fleet := (new.raw_user_meta_data->>'fleet_id')::UUID;
        EXCEPTION WHEN invalid_text_representation THEN
            IF v_clean_role = 'fleet_manager' THEN
                INSERT INTO public.fleets (name, status, tier)
                VALUES ('Flota de ' || new.email, 'past_due', 'basic')
                RETURNING id INTO v_raw_fleet;
            ELSE
                v_raw_fleet := '00000000-0000-0000-0000-000000000000'::UUID;
            END IF;
        END;
    END IF;

    -- Inyección idempotente en la tabla de dominio público
    INSERT INTO public.profiles (
        id,
        role,
        fleet_id,
        full_name,
        created_at,
        updated_at
    ) VALUES (
        new.id,
        v_clean_role,
        v_raw_fleet,
        COALESCE(new.raw_user_meta_data->>'full_name', 'No Registrado'),
        now(),
        now()
    )
    ON CONFLICT (id) DO UPDATE
    SET role = EXCLUDED.role,
        updated_at = now();

    RETURN new;
EXCEPTION WHEN OTHERS THEN
    -- Registro forense de emergencia
    RAISE WARNING 'CRITICAL_REGISTER_FAIL para UID %: %', new.id, SQLERRM;
    RETURN new;
END;
$$;

-- 3. Acoplar el trigger directamente al evento de GoTrue
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user_registration();
