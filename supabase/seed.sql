-- ============================================================================
-- MOTOR DE SEMBRADO B2B (JITSITE MVP SEEDER)
-- Despliega una cantera completa con flota, personal y maquinaria en 1 segundo.
-- ============================================================================

-- 1. IDENTIFICADORES DETERMINISTAS (Para predecir el entorno en demos y testing)
DO $$
DECLARE
    v_fleet_id UUID := 'f1ee7000-0000-4000-8000-000000000001';
    
    -- Usuarios Auth
    v_admin_id UUID := 'a1111111-0000-4000-8000-000000000000';
    v_manager_id UUID := 'b2222222-0000-4000-8000-000000000000';
    v_dispatcher_id UUID := 'c3333333-0000-4000-8000-000000000000';
    v_fitter_id UUID := 'f3333333-0000-4000-8000-000000000000';
    v_driver1_id UUID := 'd4444444-0000-4000-8000-000000000001';
    v_driver2_id UUID := 'd4444444-0000-4000-8000-000000000002';
    
    v_license_id UUID := 'f5555555-0000-0000-0000-000000000001';

    -- Hash dinámico usando pgcrypto para máxima compatibilidad con GoTrue
    v_password_hash TEXT := crypt('password123', gen_salt('bf'));
BEGIN
    RAISE NOTICE '🌱 Iniciando Sembrado Comercial B2B para JITSite Hobart...';

    -- ========================================================================
    -- FASE A: INYECCIÓN DE LA FLOTA EMPRESARIAL Y AUTH.USERS
    -- ========================================================================
    INSERT INTO public.fleets (id, name, created_at)
    VALUES (v_fleet_id, 'Hobart Quarry Operations', now())
    ON CONFLICT (id) DO NOTHING;
    INSERT INTO auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES
        (v_admin_id, 'authenticated', 'authenticated', 'admin@jitsite.com', v_password_hash, now(), '{"provider": "email", "providers": ["email"]}', json_build_object('fleet_id', v_fleet_id)::jsonb, now(), now()),
        (v_manager_id, 'authenticated', 'authenticated', 'manager@hobartquarry.com', v_password_hash, now(), '{"provider": "email", "providers": ["email"]}', json_build_object('fleet_id', v_fleet_id)::jsonb, now(), now()),
        (v_dispatcher_id, 'authenticated', 'authenticated', 'weighbridge@hobartquarry.com', v_password_hash, now(), '{"provider": "email", "providers": ["email"]}', json_build_object('fleet_id', v_fleet_id)::jsonb, now(), now()),
        (v_fitter_id, 'authenticated', 'authenticated', 'fitter@hobartquarry.com', v_password_hash, now(), '{"provider": "email", "providers": ["email"]}', json_build_object('fleet_id', v_fleet_id)::jsonb, now(), now()),
        (v_driver1_id, 'authenticated', 'authenticated', 'driver1@hobartquarry.com', v_password_hash, now(), '{"provider": "email", "providers": ["email"]}', json_build_object('fleet_id', v_fleet_id)::jsonb, now(), now()),
        (v_driver2_id, 'authenticated', 'authenticated', 'driver2@hobartquarry.com', v_password_hash, now(), '{"provider": "email", "providers": ["email"]}', json_build_object('fleet_id', v_fleet_id)::jsonb, now(), now())
    ON CONFLICT (id) DO NOTHING;

    -- ========================================================================
    -- FASE B: PERFILES JURISDICCIONALES Y FIRMAS CRIPTOGRÁFICAS (PIN: 1234)
    -- ========================================================================
    INSERT INTO public.profiles (id, fleet_id, role, full_name, pin_hash)
    VALUES
        (v_admin_id, v_fleet_id, 'super_admin', 'JITSite Admin', crypt('1234', gen_salt('bf', 4))),
        (v_manager_id, v_fleet_id, 'fleet_manager', 'Arthur Shelby', crypt('1234', gen_salt('bf', 4))),
        (v_dispatcher_id, v_fleet_id, 'dispatcher', 'Weighbridge Operator', crypt('1234', gen_salt('bf', 4))),
        (v_fitter_id, v_fleet_id, 'fitter', 'Mike Mechanic', crypt('1234', gen_salt('bf', 4))),
        (v_driver1_id, v_fleet_id, 'driver', 'John Driver', crypt('1234', gen_salt('bf', 4))),
        (v_driver2_id, v_fleet_id, 'driver', 'Sarah Hauler', crypt('1234', gen_salt('bf', 4)))
    ON CONFLICT (id) DO UPDATE SET 
        fleet_id = EXCLUDED.fleet_id, role = EXCLUDED.role, full_name = EXCLUDED.full_name, pin_hash = EXCLUDED.pin_hash;

    -- ========================================================================
    -- FASE C: CATÁLOGO DE DENSIDAD GEOLÓGICA (Tasmania Padrón Estándar)
    -- ========================================================================
    INSERT INTO public.materials (id, fleet_id, name, density_kg_m3)
    VALUES 
        ('e5f6a7b8-0000-0000-0000-000000000001', v_fleet_id, 'GRAVA (1.8 t/m3)', 1800.00),
        ('e5f6a7b8-0000-0000-0000-000000000002', v_fleet_id, 'ESTÉRIL (1.4 t/m3)', 1400.00),
        ('e5f6a7b8-0000-0000-0000-000000000003', v_fleet_id, 'MINERAL ALTO GRADO (2.4 t/m3)', 2400.00)
    ON CONFLICT DO NOTHING;

    -- ========================================================================
    -- FASE D: RUTAS LOGÍSTICAS
    -- ========================================================================
    INSERT INTO public.routes (id, fleet_id, name, origin_zone, destination_zone, est_duration_minutes)
    VALUES 
        ('a1b2c3d4-0000-0000-0000-000000000001', v_fleet_id, 'FOSO NORTE ➔ TRITURADORA PRIMARIA', 'FOSO_NORTE', 'TRITURADORA', 12),
        ('a1b2c3d4-0000-0000-0000-000000000002', v_fleet_id, 'FOSO SUR ➔ BOTADERO ESTÉRIL', 'FOSO_SUR', 'BOTADERO', 18)
    ON CONFLICT DO NOTHING;

    -- ========================================================================
    -- FASE E: LICENCIAS, FLOTA DE MAQUINARIA PESADA Y LÍNEAS BASE OEM
    -- ========================================================================
    
    INSERT INTO public.license_categories (id, code, description)
    VALUES (v_license_id, 'HR', 'Heavy Rigid Class')
    ON CONFLICT DO NOTHING;

    -- Se utilizan internal_code / category según la estructura final acodada.
    INSERT INTO public.assets (id, fleet_id, internal_code, category, status, current_engine_hours, hopper_capacity_m3, baseline_burn_rate_lph, required_license_id)
    VALUES 
        -- Camiones de Acarreo Rígidos (CAT 777) - Tolva 40 m3, Queman 45 L/H
        ('c1111111-0000-0000-0000-000000000001', v_fleet_id, 'HT-01', 'heavy_machinery', 'operational', 1205.5, 40.00, 45.00, v_license_id),
        ('c1111111-0000-0000-0000-000000000002', v_fleet_id, 'HT-02', 'heavy_machinery', 'operational', 3450.2, 40.00, 45.00, v_license_id),
        ('c1111111-0000-0000-0000-000000000003', v_fleet_id, 'HT-03', 'heavy_machinery', 'operational', 210.0, 40.00, 45.00, v_license_id),
        ('c1111111-0000-0000-0000-000000000004', v_fleet_id, 'HT-04', 'heavy_machinery', 'maintenance', 8090.8, 40.00, 45.00, v_license_id), -- Camión inhabilitado para probar el Roster
        -- Camiones Articulados (Volvo A40) - Tolva 24 m3, Queman 30 L/H
        ('c2222222-0000-0000-0000-000000000001', v_fleet_id, 'ART-01', 'heavy_machinery', 'operational', 450.5, 24.00, 30.00, v_license_id),
        ('c2222222-0000-0000-0000-000000000002', v_fleet_id, 'ART-02', 'heavy_machinery', 'operational', 1890.0, 24.00, 30.00, v_license_id),
        -- Excavadoras (Hitachi EX1200) - No cargan tonelaje en la misma forma, pero queman diésel. Queman 55 L/H
        ('e3333333-0000-0000-0000-000000000001', v_fleet_id, 'EXC-01', 'heavy_machinery', 'operational', 5600.0, 0.00, 55.00, v_license_id),
        ('e3333333-0000-0000-0000-000000000002', v_fleet_id, 'EXC-02', 'heavy_machinery', 'operational', 230.1, 0.00, 55.00, v_license_id)
    ON CONFLICT DO NOTHING;

    -- Inyectar una Etiqueta de Peligro WHS pasiva para el camión inhabilitado (HT-04)
    INSERT INTO public.asset_lockouts (asset_id, fleet_id, locked_by_operator_uid, lockout_reason, status)
    VALUES ('c1111111-0000-0000-0000-000000000004', v_fleet_id, v_driver1_id, 'FUGA DE LÍQUIDO DE DIRECCIÓN EN EJE DELANTERO DERECHO', 'ACTIVE')
    ON CONFLICT DO NOTHING;

    -- Consolidar la Vista Materializada para el Command Center
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_predictive_maintenance_roster;

    RAISE NOTICE '✅ Sembrado B2B completado con éxito. Flota operativa y lista para despacho.';
END $$;
