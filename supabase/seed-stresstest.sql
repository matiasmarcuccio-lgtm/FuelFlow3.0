-- ==========================================
-- JITSite Chaos Engineering Seed
-- Simulación de 50 camiones y 5 excavadoras
-- ==========================================
-- Project ID: aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
-- Fleet Manager: Bob (fleet@jitsite.com)

DO $$ 
DECLARE
    v_project_id UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_fleet_manager_id UUID;
    v_driver_id UUID;
    v_operator_id UUID;
    v_asset_id UUID;
    i INT;
    v_password_hash TEXT;
BEGIN
    SELECT id INTO v_fleet_manager_id FROM auth.users WHERE email = 'fleet@jitsite.com';
    IF v_fleet_manager_id IS NULL THEN
        RAISE EXCEPTION 'Fleet Manager not found. Run seed-users.js first.';
    END IF;

    v_password_hash := crypt('password123', gen_salt('bf'));

    -- 1. Crear 5 Excavadoras y Operadores
    FOR i IN 1..5 LOOP
        v_operator_id := gen_random_uuid();
        
        -- Insert auth.users
        INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
        VALUES (v_operator_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'operator_' || i || '@jitsite.com', v_password_hash, now(), '{"role": "operator"}');

        -- Update profile (auto-created by trigger)
        UPDATE public.profiles 
        SET full_name = 'Operator ' || i, role = 'operator', status = 'active'
        WHERE id = v_operator_id;

        -- Insert project member
        INSERT INTO public.project_members (project_id, user_id, role)
        VALUES (v_project_id, v_operator_id, 'operator');

        -- Insert asset (Excavator)
        v_asset_id := gen_random_uuid();
        INSERT INTO public.assets (id, asset_code, registration_number, fleet_manager_id, current_project_id, asset_type, status)
        VALUES (v_asset_id, 'EXC-TEST-' || i, 'EXC' || LPAD(i::text, 3, '0'), v_fleet_manager_id, v_project_id, 'excavator', 'available');

        -- Insert excavator_states
        INSERT INTO public.excavator_states (asset_id, operational_status, current_material)
        VALUES (v_asset_id, 'ready_to_load', 'Hard Rock');

        -- Insert active shift assignment
        INSERT INTO public.shift_assignments (vehicle_id, driver_id, status, created_at)
        VALUES (v_asset_id, v_operator_id, 'ACTIVE', CURRENT_TIMESTAMP - interval '2 hours');
    END LOOP;

    -- 2. Crear 50 Camiones y Conductores
    FOR i IN 1..50 LOOP
        v_driver_id := gen_random_uuid();
        
        -- Insert auth.users
        INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
        VALUES (v_driver_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'driver_' || i || '@jitsite.com', v_password_hash, now(), '{"role": "operator"}');

        -- Update profile (auto-created by trigger)
        UPDATE public.profiles 
        SET full_name = 'Driver ' || i, role = 'operator', status = 'active'
        WHERE id = v_driver_id;

        -- Insert project member
        INSERT INTO public.project_members (project_id, user_id, role)
        VALUES (v_project_id, v_driver_id, 'operator');

        -- Insert asset (Haul Truck)
        v_asset_id := gen_random_uuid();
        INSERT INTO public.assets (id, asset_code, registration_number, fleet_manager_id, current_project_id, asset_type, status)
        VALUES (v_asset_id, 'TRK-TEST-' || i, 'TRK' || LPAD(i::text, 3, '0'), v_fleet_manager_id, v_project_id, 'haul_truck', 'available');

        -- Insert active shift assignment (Fatigue Check: First 10 are fatigued > 11.5 hours)
        IF i <= 10 THEN
            INSERT INTO public.shift_assignments (vehicle_id, driver_id, status, created_at)
            VALUES (v_asset_id, v_driver_id, 'ACTIVE', CURRENT_TIMESTAMP - interval '11 hours 45 minutes');
        ELSE
            INSERT INTO public.shift_assignments (vehicle_id, driver_id, status, created_at)
            VALUES (v_asset_id, v_driver_id, 'ACTIVE', CURRENT_TIMESTAMP - interval '2 hours');
        END IF;
    END LOOP;

END $$;
