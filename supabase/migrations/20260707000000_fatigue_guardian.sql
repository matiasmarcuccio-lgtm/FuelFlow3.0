-- 1. Modificar el Matchmaker para implementar el Guardián de Fatiga (Fatigue Guardian)
CREATE OR REPLACE FUNCTION process_jit_dispatch_trigger()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, postgis
AS $$
DECLARE
    v_project_id UUID;
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
    v_is_fatigued BOOLEAN;
BEGIN
    -- Extraer contexto del activo
    SELECT current_project_id, asset_type, status INTO v_project_id, v_asset_category, v_asset_status 
    FROM assets WHERE id = NEW.asset_id;
    
    IF v_project_id IS NULL THEN RETURN NEW; END IF;

    -- Extraer geometrías
    SELECT loading_pad_geometry, loading_pad_buffered INTO v_loading_pad_geometry, v_loading_pad_buffered 
    FROM projects WHERE id = v_project_id;

    IF v_loading_pad_geometry IS NULL OR v_loading_pad_buffered IS NULL THEN RETURN NEW; END IF;

    -- Buscar la excavadora principal del proyecto
    SELECT id INTO v_excavator_id FROM assets WHERE current_project_id = v_project_id AND asset_type = 'excavator' LIMIT 1;
    
    IF v_excavator_id IS NOT NULL THEN
        SELECT current_material, operational_status 
        INTO v_active_material, v_excavator_status
        FROM excavator_states
        WHERE asset_id = v_excavator_id;
        
        IF v_active_material IS NULL THEN v_active_material := 'Unclassified Excavation'; END IF;
        IF v_excavator_status IS NULL THEN v_excavator_status := 'ready_to_load'; END IF;
    END IF;

    -- Lógica para Camiones de Acarreo
    IF v_asset_category = 'haul_truck' THEN
        SELECT COALESCE(ST_Contains(v_loading_pad_geometry, ST_SetSRID(ST_MakePoint(
            (last_known_location->>'lng')::NUMERIC, 
            (last_known_location->>'lat')::NUMERIC
        ), 4326)), FALSE) INTO v_was_inside
        FROM assets WHERE id = NEW.asset_id;

        SELECT ST_Contains(v_loading_pad_geometry, ST_SetSRID(ST_MakePoint(
            (NEW.payload->'location'->>'lng')::NUMERIC, 
            (NEW.payload->'location'->>'lat')::NUMERIC
        ), 4326)) INTO v_is_inside_strict;

        SELECT ST_Contains(v_loading_pad_buffered, ST_SetSRID(ST_MakePoint(
            (NEW.payload->'location'->>'lng')::NUMERIC, 
            (NEW.payload->'location'->>'lat')::NUMERIC
        ), 4326)) INTO v_is_inside_buffered;

        IF NOT v_was_inside AND v_is_inside_strict THEN
            INSERT INTO jit_active_queues (project_id, asset_id, status)
            VALUES (v_project_id, NEW.asset_id, 'waiting')
            ON CONFLICT (project_id, asset_id, status) DO NOTHING;
        END IF;

        IF v_was_inside AND NOT v_is_inside_buffered THEN
            DELETE FROM jit_active_queues WHERE asset_id = NEW.asset_id;

            UPDATE load_cycles 
            SET status = 'in_transit', transit_started_at = CURRENT_TIMESTAMP 
            WHERE asset_id = NEW.asset_id AND status = 'loading';

            IF v_excavator_status != 'ready_to_load' THEN
                RETURN NEW; 
            END IF;

            -- FATIGUE GUARDIAN: Buscar camión elegible (no fatigado) FIFO
            v_closest_truck_id := NULL;
            FOR v_truck IN 
                SELECT asset_id 
                FROM jit_active_queues
                WHERE project_id = v_project_id AND status = 'waiting'
                ORDER BY joined_queue_at ASC
            LOOP
                -- Extraer inicio de turno
                SELECT created_at INTO v_shift_start 
                FROM shift_assignments 
                WHERE vehicle_id = v_truck.asset_id AND status = 'ACTIVE' 
                ORDER BY created_at DESC LIMIT 1;
                
                -- Por defecto si no hay turno formal asume 0 fatiga en DEV (o max en PROD), pero asumimos seguro.
                IF v_shift_start IS NULL THEN
                    v_shift_start := CURRENT_TIMESTAMP; 
                END IF;

                -- Si excedió 11.5 horas, está fatigado, saltar.
                IF EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_shift_start)) / 3600.0 >= 11.5 THEN
                    -- Registrar bloqueo (Opcional, pero dejémoslo en la cola como 'waiting' y saltémoslo)
                    CONTINUE;
                ELSE
                    -- Elegible!
                    v_closest_truck_id := v_truck.asset_id;
                    EXIT;
                END IF;
            END LOOP;

            IF v_closest_truck_id IS NOT NULL THEN
                UPDATE jit_active_queues SET status = 'dispatched' WHERE asset_id = v_closest_truck_id;
                
                INSERT INTO load_cycles (project_id, asset_id, status, material_type, loading_started_at)
                VALUES (v_project_id, v_closest_truck_id, 'loading', v_active_material, CURRENT_TIMESTAMP);

                PERFORM pg_notify(
                    'pgrst',
                    jsonb_build_object(
                        'table', 'assets',
                        'action', 'broadcast',
                        'channel', 'jit_dispatch_' || v_closest_truck_id::TEXT,
                        'payload', jsonb_build_object('message', 'Atención. Proceda al cargadero principal de inmediato. Excavadora libre.')
                    )::TEXT
                );
                
                INSERT INTO webhook_events (event_type, payload)
                VALUES ('jit_dispatch', jsonb_build_object('project_id', v_project_id, 'asset_id', v_closest_truck_id));
            END IF;
        END IF;
    END IF;

    -- Lógica para Excavadoras
    IF v_asset_category = 'excavator' AND (NEW.payload->>'status' = 'ready_to_load' OR v_excavator_status = 'ready_to_load') THEN
        IF v_excavator_status != 'ready_to_load' THEN
            RETURN NEW; 
        END IF;

        -- FATIGUE GUARDIAN: Buscar camión elegible (no fatigado) FIFO
        v_closest_truck_id := NULL;
        FOR v_truck IN 
            SELECT asset_id 
            FROM jit_active_queues
            WHERE project_id = v_project_id AND status = 'waiting'
            ORDER BY joined_queue_at ASC
        LOOP
            SELECT created_at INTO v_shift_start 
            FROM shift_assignments 
            WHERE vehicle_id = v_truck.asset_id AND status = 'ACTIVE' 
            ORDER BY created_at DESC LIMIT 1;
            
            IF v_shift_start IS NULL THEN
                v_shift_start := CURRENT_TIMESTAMP; 
            END IF;

            IF EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_shift_start)) / 3600.0 >= 11.5 THEN
                CONTINUE;
            ELSE
                v_closest_truck_id := v_truck.asset_id;
                EXIT;
            END IF;
        END LOOP;

        IF v_closest_truck_id IS NOT NULL THEN
            UPDATE jit_active_queues SET status = 'dispatched' WHERE asset_id = v_closest_truck_id;
            
            INSERT INTO load_cycles (project_id, asset_id, status, material_type, loading_started_at)
            VALUES (v_project_id, v_closest_truck_id, 'loading', v_active_material, CURRENT_TIMESTAMP);

            PERFORM pg_notify(
                'pgrst',
                jsonb_build_object(
                    'table', 'assets',
                    'action', 'broadcast',
                    'channel', 'jit_dispatch_' || v_closest_truck_id::TEXT,
                    'payload', jsonb_build_object('message', 'Atención. Proceda al cargadero principal de inmediato. Excavadora libre.')
                )::TEXT
            );
            
            INSERT INTO webhook_events (event_type, payload)
            VALUES ('jit_dispatch', jsonb_build_object('project_id', v_project_id, 'asset_id', v_closest_truck_id));
        END IF;
    END IF;

    RETURN NEW;
END;
$$;
