-- ============================================================================
-- GUION DE PERITAJE FORENSE DE EXTREMO A EXTREMO (JITSITE MVP VALIDATION)
-- ============================================================================
DO $$
DECLARE
    v_test_fleet UUID := gen_random_uuid();
    v_test_operator UUID := gen_random_uuid();
    v_test_asset UUID := gen_random_uuid();
    v_test_route UUID := gen_random_uuid();
    v_test_material UUID := gen_random_uuid();
    
    v_test_license UUID := gen_random_uuid();
    v_shift_res JSONB;
    v_haul_res JSONB;
    v_fuel_res JSONB;
    v_report_res JSONB;
    
    v_shift_id UUID;
    v_error_caught BOOLEAN := false;
BEGIN
    RAISE NOTICE '▶️ [INICIO] INICIANDO PERITAJE FORENSE DE CONDUCTOS 1 AL 4...';

    -- 0. PREPARACIÓN DE ENTORNOS Y DATOS MAESTROS (MOCKING)
    INSERT INTO auth.users (id, email) VALUES (v_test_operator, 'miner.test@jitsite.com');
    
    INSERT INTO public.fleets (id, name, status) VALUES (v_test_fleet, 'TEST FLEET', 'active');
    
    INSERT INTO public.license_categories (id, code, description) VALUES (v_test_license, 'TEST_HR', 'Heavy Rigid');

    INSERT INTO public.profiles (id, fleet_id, role, full_name, pin_hash)
    VALUES (v_test_operator, v_test_fleet, 'driver', 'LIAM ODONNELL', crypt('0426', gen_salt('bf', 4)));

    -- Usamos internal_code y category para coincidir con tu esquema real en roca viva
    INSERT INTO public.assets (id, fleet_id, internal_code, category, status, current_engine_hours, hopper_capacity_m3, baseline_burn_rate_lph, required_license_id)
    VALUES (v_test_asset, v_test_fleet, 'CAT-777-01', 'heavy_machinery', 'operational', 1000.0, 20.00, 40.00, v_test_license);

    INSERT INTO public.routes (id, fleet_id, name, origin_zone, destination_zone)
    VALUES (v_test_route, v_test_fleet, 'PIT 1 ➔ TAILINGS DAM', 'SECTOR A', 'CRUSHER');

    INSERT INTO public.materials (id, fleet_id, name, density_kg_m3)
    VALUES (v_test_material, v_test_fleet, 'IRON ORE HIGH GRADE', 2400.00); -- 2.4 t/m3 -> 48 toneladas por tolva

    -- Simular sesión activa de Supabase (AAL2) para el conductor
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_test_operator, 'role', 'authenticated')::text, true);

    -- =========================================================================
    -- PRUEBA 1: CONDUCTO 1 -> INICIO DE TURNO LEGAL EN EL RELOJ WHS
    -- =========================================================================
    RAISE NOTICE '⚡ [CONDUCTO 1] Abriendo jornada laboral en reloj biológico...';
    v_shift_res := public.fn_execute_shift_action('START_SHIFT', v_test_asset);
    v_shift_id := (v_shift_res->>'shift_id')::UUID;
    
    IF (v_shift_res->>'status') != 'ACTIVE' THEN
        RAISE EXCEPTION 'FALLO FORENSE C1: El turno no se activó correctamente.';
    END IF;
    RAISE NOTICE '✅ [PASS C1] Turno activo ID: %', v_shift_id;

    -- =========================================================================
    -- PRUEBA 2: CONDUCTO 2 -> CICLO DE ACARREO Y CÁLCULO DE TONELAJE NET-ZERO
    -- =========================================================================
    RAISE NOTICE '⚡ [CONDUCTO 2] Ejecutando ciclo de acarreo en excavadora...';
    PERFORM public.fn_execute_haul_transition(v_test_asset, 'START_LOADING', v_test_route, v_test_material);
    v_haul_res := public.fn_execute_haul_transition(v_test_asset, 'FINISH_LOADING');
    
    -- Verificación matemática: 20 m3 x 2400 kg/m3 = 48.00 Toneladas exactamente
    IF (v_haul_res->>'tonnage_moved')::NUMERIC != 48.00 THEN
        RAISE EXCEPTION 'FALLO FORENSE C2: Cálculo de tonelaje erróneo. Esperado: 48.00, Obtenido: %', v_haul_res->>'tonnage_moved';
    END IF;

    PERFORM public.fn_execute_haul_transition(v_test_asset, 'CONFIRM_DUMP');
    v_haul_res := public.fn_execute_haul_transition(v_test_asset, 'COMPLETE_CYCLE');
    RAISE NOTICE '✅ [PASS C2] Ciclo cerrado. Toneladas sumadas al libro mayor: % t', v_haul_res->>'tonnage_added';

    -- =========================================================================
    -- PRUEBA 3: CONDUCTO 3 -> REPOSTAJE LEGAL VS. SIMULACIÓN DE ROBO (SIFÓN)
    -- =========================================================================
    RAISE NOTICE '⚡ [CONDUCTO 3] Inyectando recarga de combustible sospechosa de robo...';
    -- El conductor reporta 150 Litros pero el horómetro solo avanzó 0.1 horas (1500 L/Hora -> Imposible físicamente)
    v_fuel_res := public.fn_submit_fuel_log(v_test_asset, 150.00, 1000.1, 1.85, 'RECARGA EN RAMPA');
    
    IF (v_fuel_res->>'status') != 'THEFT_SUSPECTED' THEN
        RAISE EXCEPTION 'FALLO FORENSE C3: El motor no detectó la anomalía de robo. Estado devuelto: %', v_fuel_res->>'status';
    END IF;
    RAISE NOTICE '✅ [PASS C3] Algoritmo FuelFlow interceptó robo en terreno. Estado: %', v_fuel_res->>'status';

    -- =========================================================================
    -- PRUEBA 4: ENCLAVAMIENTO CRUZADO -> GUILLOTINA DE FATIGA WHS
    -- =========================================================================
    RAISE NOTICE '⚡ [ENCLAVAMIENTO] Forzando fatiga ilegal (6 horas continuas sin descanso)...';
    -- Manipulamos el reloj interno en Capa 0 para simular que el conductor excedió el límite de 5 horas
    UPDATE public.shift_logs 
    SET continuous_work_seconds = 21600, last_state_change_at = now() - interval '6 hours'
    WHERE id = v_shift_id;

    -- Disparar un check pasivo para que el motor biológico deje caer la guillotina
    PERFORM public.fn_execute_shift_action('CHECK_STATUS', v_test_asset);

    -- Verificar que la máquina cambió a maintenance automáticamente
    IF (SELECT status FROM public.assets WHERE id = v_test_asset) != 'maintenance' THEN
        RAISE EXCEPTION 'FALLO DE ENCLAVAMIENTO: La maquinaria no fue inhabilitada tras el exceso de fatiga. Status actual: %', (SELECT status FROM public.assets WHERE id = v_test_asset);
    END IF;

    -- INTENTO DE SABOTAJE: El conductor fatigado intenta iniciar un nuevo ciclo de acarreo
    RAISE NOTICE '⚡ [PRUEBA DE ESTRÉS] Intentando iniciar ciclo con operador en bloqueo de fatiga...';
    BEGIN
        PERFORM public.fn_execute_haul_transition(v_test_asset, 'START_LOADING', v_test_route, v_test_material);
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%WHS_INTERLOCK%' OR SQLERRM LIKE '%WHS_LOCKOUT%' THEN
            v_error_caught := true;
            RAISE NOTICE '✅ [PASS ENCLAVAMIENTO] Aduana rechazó ciclo ilegal por fatiga: "%"', SQLERRM;
        ELSE
            RAISE EXCEPTION 'FALLO FORENSE: El error devuelto no fue una violación WHS: %', SQLERRM;
        END IF;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'PELIGRO LEGAL: El sistema permitió cargar tierra a un conductor legalmente fatigado.';
    END IF;

    -- =========================================================================
    -- PRUEBA 5: CONDUCTO 4 -> AUDITORÍA TRIBUTARIA Y EXCLUSIÓN DE COMBUSTIBLE ROBADO
    -- =========================================================================
    RAISE NOTICE '⚡ [CONDUCTO 4] Conciliando libro mayor tributario ATO para crédito fiscal...';
    
    -- Elevamos privilegios a Fleet Manager para poder emitir el reporte legal
    UPDATE public.profiles SET role = 'fleet_manager' WHERE id = v_test_operator;
    
    v_report_res := public.fn_export_regulatory_report('ATO_FUEL_REBATE');
    
    -- VERIFICACIÓN FISCAL CRÍTICA: Como los 150L inyectados fueron marcados como THEFT_SUSPECTED,
    -- el reembolso ATO estimado DEBE ser estrictamente $0.00 AUD (No se pide crédito fiscal por diésel robado).
    IF (v_report_res->'data'->0->>'estimated_ato_rebate_aud')::NUMERIC != 0.00 THEN
        RAISE EXCEPTION 'FALLO FISCAL ATO: El libro mayor está intentando reclamar créditos por combustible robado.';
    END IF;
    RAISE NOTICE '✅ [PASS C4] Libro mayor ATO conciliado. Diésel robado excluido del crédito fiscal.';

    -- =========================================================================
    -- LIMPIEZA FORENSE (ROLLBACK DE PRUEBAS PARA NO CONTAMINAR PRODUCCIÓN)
    -- =========================================================================
    RAISE NOTICE '🎯 [ÉXITO TOTAL] LOS 4 CONDUCTOS LOGÍSTICOS OPERAN CON PRECISIÓN MILITAR.';
    RAISE NOTICE '🧹 Revirtiendo transacciones de peritaje temporal...';
    RAISE EXCEPTION 'SIMULACRO_COMPLETADO_EXITOSAMENTE' USING ERRCODE = 'P0001';

EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'SIMULACRO_COMPLETADO_EXITOSAMENTE' THEN
        RAISE NOTICE '🏁 PERITAJE FINALIZADO SIN ERRORES. TU ARQUITECTURA ES IMPERMEABLE.';
    ELSE
        RAISE NOTICE '🛑 ERROR FATAL DURANTE EL SIMULACRO: % (Código: %)', SQLERRM, SQLSTATE;
        RAISE;
    END IF;
END;
$$;
