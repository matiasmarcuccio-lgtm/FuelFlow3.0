-- 1. Registrar el nuevo rol operativo en la plataforma
ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'weighbridge_operator';

-- 2. Crear el ENUM del ciclo de vida logístico-financiero
CREATE TYPE cycle_status AS ENUM ('loading', 'in_transit', 'dumped', 'reconciled');

-- 3. Crear la tabla de control de masa y dockets digitales
CREATE TABLE load_cycles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
    asset_id UUID NOT NULL REFERENCES assets(id) ON DELETE RESTRICT, -- El Camión
    driver_id UUID REFERENCES profiles(id) ON DELETE RESTRICT,
    weighbridge_operator_id UUID REFERENCES profiles(id) ON DELETE RESTRICT,
    
    material_type TEXT NOT NULL DEFAULT 'Unclassified Excavation',
    gross_weight NUMERIC(6,2), -- Captura en báscula (Toneladas)
    tare_weight NUMERIC(6,2),  -- Peso vacío del camión
    net_weight NUMERIC(6,2) GENERATED ALWAYS AS (gross_weight - tare_weight) STORED,
    
    status cycle_status NOT NULL DEFAULT 'loading',
    
    loading_started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    transit_started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 4. Habilitar seguridad RLS estricta para CoR
ALTER TABLE load_cycles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Weighbridge operators can update active dockets"
    ON load_cycles
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.id = auth.uid()
            AND profiles.role = 'weighbridge_operator'
        ) AND status = 'in_transit'
    )
    WITH CHECK (
        status IN ('dumped', 'reconciled')
    );

CREATE POLICY "Crew can view their own project cycles"
    ON load_cycles
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM project_members
            WHERE project_members.project_id = load_cycles.project_id
            AND project_members.user_id = auth.uid()
        )
    );

-- 5. Modificar el Trigger Espacial (Matchmaker) para incluir la lógica del Motor de Dockets
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
BEGIN
    -- Extraer contexto del activo
    SELECT current_project_id, asset_type, status INTO v_project_id, v_asset_category, v_asset_status 
    FROM assets WHERE id = NEW.asset_id;
    
    IF v_project_id IS NULL THEN RETURN NEW; END IF;

    -- Extraer geometrías (Histéresis Espacial materializada)
    SELECT loading_pad_geometry, loading_pad_buffered INTO v_loading_pad_geometry, v_loading_pad_buffered 
    FROM projects WHERE id = v_project_id;

    IF v_loading_pad_geometry IS NULL OR v_loading_pad_buffered IS NULL THEN RETURN NEW; END IF;

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
            -- Eliminarlo de la cola activa si estaba (sin importar si estaba waiting o dispatched)
            DELETE FROM jit_active_queues WHERE asset_id = NEW.asset_id;

            -- DIGITAL DOCKET ENGINE: Transicionar el ciclo a in_transit para el camión saliente
            UPDATE load_cycles 
            SET status = 'in_transit', transit_started_at = CURRENT_TIMESTAMP 
            WHERE asset_id = NEW.asset_id AND status = 'loading';

            -- MATCHMAKER: Disparar asignación al camión más antiguo de la cola (FIFO)
            SELECT asset_id INTO v_closest_truck_id
            FROM jit_active_queues
            WHERE project_id = v_project_id AND status = 'waiting'
            ORDER BY joined_queue_at ASC
            LIMIT 1;

            IF v_closest_truck_id IS NOT NULL THEN
                UPDATE jit_active_queues SET status = 'dispatched' WHERE asset_id = v_closest_truck_id;
                
                -- DIGITAL DOCKET ENGINE: Crear el ciclo en estado loading para el camión despachado
                INSERT INTO load_cycles (project_id, asset_id, status, loading_started_at)
                VALUES (v_project_id, v_closest_truck_id, 'loading', CURRENT_TIMESTAMP);

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
                
                -- Registrar el hito logístico en el sumidero (Outbox Pattern)
                INSERT INTO webhook_events (event_type, payload)
                VALUES ('jit_dispatch', jsonb_build_object('project_id', v_project_id, 'asset_id', v_closest_truck_id));
            END IF;
        END IF;
    END IF;

    -- Lógica para Excavadoras (Excavators)
    IF v_asset_category = 'excavator' AND (NEW.payload->>'status' = 'ready_to_load') THEN
        -- MATCHMAKER: Una excavadora reporta estar lista. Buscar camión FIFO.
        SELECT asset_id INTO v_closest_truck_id
        FROM jit_active_queues
        WHERE project_id = v_project_id AND status = 'waiting'
        ORDER BY joined_queue_at ASC
        LIMIT 1;

        IF v_closest_truck_id IS NOT NULL THEN
            UPDATE jit_active_queues SET status = 'dispatched' WHERE asset_id = v_closest_truck_id;
            
            -- DIGITAL DOCKET ENGINE: Crear el ciclo en estado loading para el camión despachado
            INSERT INTO load_cycles (project_id, asset_id, status, loading_started_at)
            VALUES (v_project_id, v_closest_truck_id, 'loading', CURRENT_TIMESTAMP);

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
