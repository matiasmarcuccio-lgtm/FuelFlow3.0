-- 1. Modificar sync_asset_status_on_defect para emitir 'maintenance_critical' con desnormalización
CREATE OR REPLACE FUNCTION sync_asset_status_on_defect()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_project_name TEXT;
    v_asset_code TEXT;
    v_reporter_name TEXT;
    v_payload JSONB;
BEGIN
    IF NEW.status = 'reported' THEN
        -- Retirar el camión/excavadora del juego operativo inmediatamente
        UPDATE assets 
        SET status = 'out_of_service'
        WHERE id = NEW.asset_id;

        -- Evacuación Lógica de la Cola (Prevención de Cuello de Botella Fantasma)
        DELETE FROM jit_active_queues 
        WHERE asset_id = NEW.asset_id;
        
        -- Abortar ciclos de carga vulnerables
        -- Si estaba cargando o en tránsito, el material no llegará a la báscula de forma natural.
        UPDATE load_cycles 
        SET status = 'reconciled', 
            material_type = 'ABORTED_DEFECT',
            completed_at = CURRENT_TIMESTAMP
        WHERE asset_id = NEW.asset_id AND status IN ('loading', 'in_transit');

        -- Capturar datos literales en una sola operación indexada
        SELECT p.name, a.asset_code, COALESCE(pr.full_name, 'Usuario Desconocido')
        INTO v_project_name, v_asset_code, v_reporter_name
        FROM assets a
        JOIN projects p ON a.current_project_id = p.id
        LEFT JOIN profiles pr ON pr.id = NEW.reported_by
        WHERE a.id = NEW.asset_id;

        -- Construir el payload auto-contenido
        v_payload := jsonb_build_object(
            'project_id', NEW.project_id,
            'project_name', v_project_name,
            'asset_id', NEW.asset_id,
            'asset_code', v_asset_code,
            'reported_by_name', v_reporter_name,
            'defect_description', NEW.defect_description,
            'timestamp', NEW.reported_at,
            'alert_type', 'maintenance_critical',
            'message', format('CRITICAL: El activo %s ha sido inmovilizado por %s en %s debido a: %s. Requiere intervención inmediata del taller.', 
                              v_asset_code, v_reporter_name, v_project_name, NEW.defect_description)
        );

        -- Expulsar al Outbox
        INSERT INTO webhook_events (event_type, payload)
        VALUES ('maintenance_critical', v_payload);

    ELSIF NEW.status = 'rectified' AND OLD.status != 'rectified' THEN
        -- Restaurar el camión al estado limpio listo para operar
        UPDATE assets 
        SET status = 'available'
        WHERE id = NEW.asset_id;
    END IF;
    RETURN NEW;
END;
$$;

-- 2. Modificar process_jit_dispatch_trigger para emitir 'compliance_violation' por fatiga
CREATE OR REPLACE FUNCTION process_jit_dispatch_trigger()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, postgis
AS $$
DECLARE
    v_project_id UUID;
    v_project_name TEXT;
    v_loading_pad_geometry GEOMETRY;
    v_loading_pad_buffered GEOMETRY;
    v_was_inside BOOLEAN;
    v_is_inside_strict BOOLEAN;
    v_is_inside_buffered BOOLEAN;
    v_closest_truck_id UUID;
    v_asset_category VARCHAR;
    v_asset_status VARCHAR;
    v_active_material TEXT := 'Unclassified Excavation';
    v_excavator_status excavator_status := 'ready_to_load';
    v_excavator_id UUID;
    v_truck RECORD;
    v_shift_start TIMESTAMPTZ;
    v_driver_id UUID;
    v_driver_name TEXT;
    v_asset_code TEXT;
    v_shift_duration_hours NUMERIC;
BEGIN
    -- Extraer contexto del activo
    SELECT a.current_project_id, a.asset_type, a.status, p.name 
    INTO v_project_id, v_asset_category, v_asset_status, v_project_name
    FROM assets a
    LEFT JOIN projects p ON p.id = a.current_project_id
    WHERE a.id = NEW.asset_id;
    
    IF v_project_id IS NULL THEN RETURN NEW; END IF;

    SELECT loading_pad_geometry, loading_pad_buffered INTO v_loading_pad_geometry, v_loading_pad_buffered 
    FROM projects WHERE id = v_project_id;

    IF v_loading_pad_geometry IS NULL OR v_loading_pad_buffered IS NULL THEN RETURN NEW; END IF;

    SELECT id INTO v_excavator_id FROM assets WHERE current_project_id = v_project_id AND asset_type = 'excavator' LIMIT 1;
    
    IF v_excavator_id IS NOT NULL THEN
        SELECT current_material, operational_status INTO v_active_material, v_excavator_status FROM excavator_states WHERE asset_id = v_excavator_id;
        IF v_active_material IS NULL THEN v_active_material := 'Unclassified Excavation'; END IF;
        IF v_excavator_status IS NULL THEN v_excavator_status := 'ready_to_load'; END IF;
    END IF;

    IF v_asset_category = 'haul_truck' THEN
        SELECT COALESCE(ST_Contains(v_loading_pad_geometry, ST_SetSRID(ST_MakePoint((last_known_location->>'lng')::NUMERIC, (last_known_location->>'lat')::NUMERIC), 4326)), FALSE) INTO v_was_inside FROM assets WHERE id = NEW.asset_id;
        SELECT ST_Contains(v_loading_pad_geometry, ST_SetSRID(ST_MakePoint((NEW.payload->'location'->>'lng')::NUMERIC, (NEW.payload->'location'->>'lat')::NUMERIC), 4326)) INTO v_is_inside_strict;
        SELECT ST_Contains(v_loading_pad_buffered, ST_SetSRID(ST_MakePoint((NEW.payload->'location'->>'lng')::NUMERIC, (NEW.payload->'location'->>'lat')::NUMERIC), 4326)) INTO v_is_inside_buffered;

        IF NOT v_was_inside AND v_is_inside_strict THEN
            INSERT INTO jit_active_queues (project_id, asset_id, status) VALUES (v_project_id, NEW.asset_id, 'waiting') ON CONFLICT (project_id, asset_id, status) DO NOTHING;
        END IF;

        IF v_was_inside AND NOT v_is_inside_buffered THEN
            DELETE FROM jit_active_queues WHERE asset_id = NEW.asset_id;
            UPDATE load_cycles SET status = 'in_transit', transit_started_at = CURRENT_TIMESTAMP WHERE asset_id = NEW.asset_id AND status = 'loading';

            IF v_excavator_status != 'ready_to_load' THEN RETURN NEW; END IF;

            v_closest_truck_id := NULL;
            FOR v_truck IN SELECT asset_id FROM jit_active_queues WHERE project_id = v_project_id AND status = 'waiting' ORDER BY joined_queue_at ASC LOOP
                SELECT created_at, driver_id INTO v_shift_start, v_driver_id FROM shift_assignments WHERE vehicle_id = v_truck.asset_id AND status = 'ACTIVE' ORDER BY created_at DESC LIMIT 1;
                IF v_shift_start IS NULL THEN v_shift_start := CURRENT_TIMESTAMP; END IF;

                v_shift_duration_hours := EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_shift_start)) / 3600.0;
                
                IF v_shift_duration_hours >= 11.5 THEN
                    -- DESNORMALIZACIÓN TÁCTICA
                    SELECT a.asset_code, COALESCE(pr.full_name, 'Usuario Desconocido') INTO v_asset_code, v_driver_name
                    FROM assets a LEFT JOIN profiles pr ON pr.id = v_driver_id WHERE a.id = v_truck.asset_id;
                    
                    INSERT INTO webhook_events (event_type, payload)
                    VALUES ('compliance_violation', jsonb_build_object(
                        'project_id', v_project_id,
                        'project_name', v_project_name,
                        'asset_id', v_truck.asset_id,
                        'asset_code', v_asset_code,
                        'driver_name', v_driver_name,
                        'shift_duration_hours', ROUND(v_shift_duration_hours::numeric, 2),
                        'legal_limit_hours', 11.5,
                        'timestamp', CURRENT_TIMESTAMP,
                        'alert_type', 'compliance_violation',
                        'message', format('ALERTA CoR: Operador %s ha sido expulsado de la cola JIT en el activo %s. Tiempo de conducción actual: %s horas (Límite NHVR: 11.5h). Detenga la máquina de forma segura.', v_driver_name, v_asset_code, ROUND(v_shift_duration_hours::numeric, 2))
                    ));
                    CONTINUE;
                ELSE
                    v_closest_truck_id := v_truck.asset_id;
                    EXIT;
                END IF;
            END LOOP;

            IF v_closest_truck_id IS NOT NULL THEN
                UPDATE jit_active_queues SET status = 'dispatched' WHERE asset_id = v_closest_truck_id;
                INSERT INTO load_cycles (project_id, asset_id, status, material_type, loading_started_at) VALUES (v_project_id, v_closest_truck_id, 'loading', v_active_material, CURRENT_TIMESTAMP);
                PERFORM pg_notify('pgrst', jsonb_build_object('table', 'assets', 'action', 'broadcast', 'channel', 'jit_dispatch_' || v_closest_truck_id::TEXT, 'payload', jsonb_build_object('message', 'Atención. Proceda al cargadero principal de inmediato. Excavadora libre.'))::TEXT);
                INSERT INTO webhook_events (event_type, payload) VALUES ('jit_dispatch', jsonb_build_object('project_id', v_project_id, 'asset_id', v_closest_truck_id));
            END IF;
        END IF;
    END IF;

    -- Lógica para Excavadoras
    IF v_asset_category = 'excavator' AND (NEW.payload->>'status' = 'ready_to_load' OR v_excavator_status = 'ready_to_load') THEN
        IF v_excavator_status != 'ready_to_load' THEN RETURN NEW; END IF;

        v_closest_truck_id := NULL;
        FOR v_truck IN SELECT asset_id FROM jit_active_queues WHERE project_id = v_project_id AND status = 'waiting' ORDER BY joined_queue_at ASC LOOP
            SELECT created_at, driver_id INTO v_shift_start, v_driver_id FROM shift_assignments WHERE vehicle_id = v_truck.asset_id AND status = 'ACTIVE' ORDER BY created_at DESC LIMIT 1;
            IF v_shift_start IS NULL THEN v_shift_start := CURRENT_TIMESTAMP; END IF;

            v_shift_duration_hours := EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_shift_start)) / 3600.0;
            
            IF v_shift_duration_hours >= 11.5 THEN
                -- DESNORMALIZACIÓN TÁCTICA
                SELECT a.asset_code, COALESCE(pr.full_name, 'Usuario Desconocido') INTO v_asset_code, v_driver_name
                FROM assets a LEFT JOIN profiles pr ON pr.id = v_driver_id WHERE a.id = v_truck.asset_id;
                
                INSERT INTO webhook_events (event_type, payload)
                VALUES ('compliance_violation', jsonb_build_object(
                    'project_id', v_project_id,
                    'project_name', v_project_name,
                    'asset_id', v_truck.asset_id,
                    'asset_code', v_asset_code,
                    'driver_name', v_driver_name,
                    'shift_duration_hours', ROUND(v_shift_duration_hours::numeric, 2),
                    'legal_limit_hours', 11.5,
                    'timestamp', CURRENT_TIMESTAMP,
                    'alert_type', 'compliance_violation',
                    'message', format('ALERTA CoR: Operador %s ha sido expulsado de la cola JIT en el activo %s. Tiempo de conducción actual: %s horas (Límite NHVR: 11.5h). Detenga la máquina de forma segura.', v_driver_name, v_asset_code, ROUND(v_shift_duration_hours::numeric, 2))
                ));
                CONTINUE;
            ELSE
                v_closest_truck_id := v_truck.asset_id;
                EXIT;
            END IF;
        END LOOP;

        IF v_closest_truck_id IS NOT NULL THEN
            UPDATE jit_active_queues SET status = 'dispatched' WHERE asset_id = v_closest_truck_id;
            INSERT INTO load_cycles (project_id, asset_id, status, material_type, loading_started_at) VALUES (v_project_id, v_closest_truck_id, 'loading', v_active_material, CURRENT_TIMESTAMP);
            PERFORM pg_notify('pgrst', jsonb_build_object('table', 'assets', 'action', 'broadcast', 'channel', 'jit_dispatch_' || v_closest_truck_id::TEXT, 'payload', jsonb_build_object('message', 'Atención. Proceda al cargadero principal de inmediato. Excavadora libre.'))::TEXT);
            INSERT INTO webhook_events (event_type, payload) VALUES ('jit_dispatch', jsonb_build_object('project_id', v_project_id, 'asset_id', v_closest_truck_id));
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- 3. Modificar sweep_stagnant_queues para emitir 'logistic_bottleneck'
CREATE OR REPLACE FUNCTION sweep_stagnant_queues()
RETURNS void 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_stagnant RECORD;
    v_project_name TEXT;
    v_asset_code TEXT;
    v_wait_time_minutes NUMERIC;
BEGIN
    FOR v_stagnant IN 
        SELECT q.id, q.project_id, q.asset_id, q.joined_queue_at 
        FROM jit_active_queues q
        WHERE q.status = 'waiting' 
          AND (CURRENT_TIMESTAMP - q.joined_queue_at) > interval '15 minutes'
          AND NOT EXISTS (
              SELECT 1 FROM webhook_events 
              WHERE event_type = 'logistic_bottleneck' 
                AND payload->>'asset_id' = q.asset_id::TEXT
                AND created_at > (CURRENT_TIMESTAMP - interval '1 hour')
          )
    LOOP
        v_wait_time_minutes := EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_stagnant.joined_queue_at)) / 60.0;
        
        SELECT p.name, a.asset_code 
        INTO v_project_name, v_asset_code
        FROM assets a
        JOIN projects p ON a.current_project_id = p.id
        WHERE a.id = v_stagnant.asset_id;

        -- Empujar alerta al sumidero para n8n con payload desnormalizado
        INSERT INTO webhook_events (event_type, payload)
        VALUES ('logistic_bottleneck', jsonb_build_object(
            'project_id', v_stagnant.project_id, 
            'project_name', v_project_name,
            'asset_id', v_stagnant.asset_id,
            'asset_code', v_asset_code,
            'waiting_minutes', ROUND(v_wait_time_minutes::numeric, 2),
            'threshold_minutes', 15,
            'timestamp', CURRENT_TIMESTAMP,
            'alert_type', 'logistic_bottleneck',
            'message', format('CUELLO DE BOTELLA: Vehículo %s inactivo en cargadero de %s superó umbral de 15 minutos (Lleva %s min).', v_asset_code, v_project_name, ROUND(v_wait_time_minutes::numeric, 2))
        ));
    END LOOP;
END;
$$;
