CREATE OR REPLACE FUNCTION public.handle_new_user_registration()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_raw_role TEXT;
    v_clean_role TEXT;
    v_raw_fleet UUID;
BEGIN
    v_raw_role := COALESCE(new.raw_user_meta_data->>'role', 'driver');
    v_clean_role := LOWER(TRIM(v_raw_role));

    IF v_clean_role NOT IN ('driver', 'fitter', 'supervisor', 'fleet_manager', 'super_admin') THEN
        v_clean_role := 'driver';
    END IF;

    IF (new.raw_user_meta_data->>'fleet_id') IS NULL OR TRIM(new.raw_user_meta_data->>'fleet_id') = '' THEN
        IF v_clean_role = 'fleet_manager' THEN
            INSERT INTO public.fleets (name, status, tier)
            VALUES ('Flota de ' || new.email, 'past_due', 'tier_1')
            RETURNING id INTO v_raw_fleet;
        ELSE
            v_raw_fleet := '00000000-0000-0000-0000-000000000000'::UUID;
        END IF;
    ELSE
        BEGIN
            v_raw_fleet := (new.raw_user_meta_data->>'fleet_id')::UUID;
        EXCEPTION WHEN invalid_text_representation THEN
            IF v_clean_role = 'fleet_manager' THEN
                INSERT INTO public.fleets (name, status, tier)
                VALUES ('Flota de ' || new.email, 'past_due', 'tier_1')
                RETURNING id INTO v_raw_fleet;
            ELSE
                v_raw_fleet := '00000000-0000-0000-0000-000000000000'::UUID;
            END IF;
        END;
    END IF;

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
    RAISE WARNING 'CRITICAL_REGISTER_FAIL para UID %: %', new.id, SQLERRM;
    RETURN new;
END;
$$;
