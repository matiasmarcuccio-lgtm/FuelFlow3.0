-- 1. ENUM para el semáforo de despacho JIT de la excavadora
CREATE TYPE excavator_status AS ENUM ('ready_to_load', 'relocating', 'rock_breaking', 'standby');

-- 2. Tabla de extensión operativa desacoplada
CREATE TABLE excavator_states (
    asset_id UUID PRIMARY KEY REFERENCES assets(id) ON DELETE RESTRICT,
    operational_status excavator_status NOT NULL DEFAULT 'standby',
    current_material TEXT NOT NULL DEFAULT 'Unclassified Excavation',
    geological_block TEXT, -- Identificador del corte topográfico
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 3. Habilitar RLS para control en cabina
ALTER TABLE excavator_states ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Excavator operators can mutate their own state"
    ON excavator_states
    FOR UPDATE
    TO authenticated
    USING (auth.uid() IN (
        SELECT user_id FROM project_members WHERE project_id = (
            SELECT project_id FROM assets WHERE id = excavator_states.asset_id
        )
    ));

CREATE POLICY "Public read for fleet orchestration"
    ON excavator_states FOR SELECT TO authenticated USING (true);

-- 4. Modificar el Matchmaker para extraer material y validar el semáforo JIT
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
BEGIN
    -- Extraer contexto del activo
    SELECT current_project_id, asset_type, status INTO v_project_id, v_asset_category, v_asset_status 
    FROM assets WHERE id = NEW.asset_id;
    
    IF v_project_id IS NULL THEN RETURN NEW; END IF;

    -- Extraer geometrías (Histéresis Espacial materializada)
    SELECT loading_pad_geometry, loading_pad_buffered INTO v_loading_pad_geometry, v_loading_pad_buffered 
    FROM projects WHERE id = v_project_id;

    IF v_loading_pad_geometry IS NULL OR v_loading_pad_buffered IS NULL THEN RETURN NEW; END IF;

    -- Buscar la excavadora principal del proyecto (asumiendo 1 por ahora para el PoC JIT)
    SELECT id INTO v_excavator_id FROM assets WHERE current_project_id = v_project_id AND asset_type = 'excavator' LIMIT 1;
    
    IF v_excavator_id IS NOT NULL THEN
        -- Extraer el estado real y el material del silicio de la excavadora
        SELECT current_material, operational_status 
        INTO v_active_material, v_excavator_status
        FROM excavator_states
        WHERE asset_id = v_excavator_id;
        
        -- Default fallbacks if not found
        IF v_active_material IS NULL THEN v_active_material := 'Unclassified Excavation'; END IF;
        IF v_excavator_status IS NULL THEN v_excavator_status := 'ready_to_load'; END IF;
    END IF;

    -- Lógica para Camiones de Acarreo (Haul Trucks)
    IF v_asset_category = 'haul_truck' THEN
        -- Evaluar cruce de fronteras
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

        -- Condición Entrada: Entra al pad estricto y no está en la cola
        IF NOT v_was_inside AND v_is_inside_strict THEN
            INSERT INTO jit_active_queues (project_id, asset_id, status)
            VALUES (v_project_id, NEW.asset_id, 'waiting')
            ON CONFLICT (project_id, asset_id, status) DO NOTHING;
        END IF;

        -- Condición Salida: Sale del pad holgado (libera el espacio)
        IF v_was_inside AND NOT v_is_inside_buffered THEN
            -- Eliminarlo de la cola activa si estaba
            DELETE FROM jit_active_queues WHERE asset_id = NEW.asset_id;

            -- DIGITAL DOCKET ENGINE: Transicionar el ciclo a in_transit para el camión saliente
            UPDATE load_cycles 
            SET status = 'in_transit', transit_started_at = CURRENT_TIMESTAMP 
            WHERE asset_id = NEW.asset_id AND status = 'loading';

            -- SALVAGUARDA: Si la excavadora se está moviendo o rompiendo roca, suspender el emparejamiento JIT
            IF v_excavator_status != 'ready_to_load' THEN
                RETURN NEW; -- No se extrae camión de la cola FIFO, el frente está pausado
            END IF;

            -- MATCHMAKER: Disparar asignación al camión más antiguo de la cola (FIFO)
            SELECT asset_id INTO v_closest_truck_id
            FROM jit_active_queues
            WHERE project_id = v_project_id AND status = 'waiting'
            ORDER BY joined_queue_at ASC
            LIMIT 1;

            IF v_closest_truck_id IS NOT NULL THEN
                UPDATE jit_active_queues SET status = 'dispatched' WHERE asset_id = v_closest_truck_id;
                
                -- DIGITAL DOCKET ENGINE: Crear el ciclo en estado loading para el camión despachado (usando la receta)
                INSERT INTO load_cycles (project_id, asset_id, status, material_type, loading_started_at)
                VALUES (v_project_id, v_closest_truck_id, 'loading', v_active_material, CURRENT_TIMESTAMP);

                -- Despacho Acústico
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

    -- Lógica para Excavadoras (Excavators)
    IF v_asset_category = 'excavator' AND (NEW.payload->>'status' = 'ready_to_load' OR v_excavator_status = 'ready_to_load') THEN
        -- MATCHMAKER: Una excavadora reporta estar lista.
        
        -- SALVAGUARDA
        IF v_excavator_status != 'ready_to_load' THEN
            RETURN NEW; 
        END IF;

        SELECT asset_id INTO v_closest_truck_id
        FROM jit_active_queues
        WHERE project_id = v_project_id AND status = 'waiting'
        ORDER BY joined_queue_at ASC
        LIMIT 1;

        IF v_closest_truck_id IS NOT NULL THEN
            UPDATE jit_active_queues SET status = 'dispatched' WHERE asset_id = v_closest_truck_id;
            
            -- DIGITAL DOCKET ENGINE
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
