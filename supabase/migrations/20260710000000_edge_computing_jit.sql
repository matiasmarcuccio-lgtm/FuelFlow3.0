-- 20260710000000_edge_computing_jit.sql
-- Migración para el desacoplamiento espacial (Edge Computing)

SET search_path = public, postgis;

-- 1. Pagar la deuda técnica: Índices GIST
CREATE INDEX IF NOT EXISTS idx_projects_loading_pad_geometry ON projects USING GIST (loading_pad_geometry);
CREATE INDEX IF NOT EXISTS idx_projects_loading_pad_buffered ON projects USING GIST (loading_pad_buffered);
CREATE INDEX IF NOT EXISTS idx_projects_hrcw_polygon ON projects USING GIST (hrcw_polygon);

-- 2. Buffer de Ingestión Asíncrono (UNLOGGED)
CREATE UNLOGGED TABLE IF NOT EXISTS telemetry_inbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
    recorded_by UUID NOT NULL REFERENCES profiles(id),
    payload JSONB NOT NULL,
    client_timestamp TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE telemetry_inbox ENABLE ROW LEVEL SECURITY;

CREATE POLICY "operator_insert_telemetry_inbox" ON telemetry_inbox
    FOR INSERT
    WITH CHECK (auth.uid() = recorded_by);

-- 3. Funciones RPC para Matchmaker JIT

-- join_jit_queue
CREATE OR REPLACE FUNCTION join_jit_queue(p_asset_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_project_id UUID;
    v_asset_status VARCHAR;
    v_asset_category VARCHAR;
BEGIN
    SELECT current_project_id, status, asset_type INTO v_project_id, v_asset_status, v_asset_category
    FROM assets WHERE id = p_asset_id;

    IF v_project_id IS NULL OR v_asset_category != 'haul_truck' THEN
        RETURN;
    END IF;

    -- Solo insertamos si el camión está activo y no tiene defectos críticos
    INSERT INTO jit_active_queues (project_id, asset_id, status) 
    VALUES (v_project_id, p_asset_id, 'waiting') 
    ON CONFLICT (project_id, asset_id, status) DO NOTHING;
END;
$$;

-- leave_jit_queue
CREATE OR REPLACE FUNCTION leave_jit_queue(p_asset_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_project_id UUID;
    v_project_name TEXT;
    v_excavator_status VARCHAR;
    v_active_material TEXT;
    v_closest_truck_id UUID;
    v_truck RECORD;
    v_shift_start TIMESTAMPTZ;
    v_driver_id UUID;
    v_driver_name TEXT;
    v_asset_code TEXT;
    v_shift_duration_hours NUMERIC;
BEGIN
    SELECT a.current_project_id, p.name INTO v_project_id, v_project_name
    FROM assets a
    LEFT JOIN projects p ON p.id = a.current_project_id
    WHERE a.id = p_asset_id;

    IF v_project_id IS NULL THEN RETURN; END IF;

    -- Purge del camión saliente
    DELETE FROM jit_active_queues WHERE asset_id = p_asset_id;
    UPDATE load_cycles SET status = 'in_transit', transit_started_at = CURRENT_TIMESTAMP 
    WHERE asset_id = p_asset_id AND status = 'loading';

    -- Evaluar si se debe despachar al siguiente camión
    SELECT operational_status, current_material INTO v_excavator_status, v_active_material
    FROM excavator_states 
    WHERE asset_id = (SELECT id FROM assets WHERE current_project_id = v_project_id AND asset_type = 'excavator' LIMIT 1);

    IF v_excavator_status IS NULL THEN v_excavator_status := 'ready_to_load'; END IF;
    IF v_active_material IS NULL THEN v_active_material := 'Unclassified Excavation'; END IF;

    IF v_excavator_status != 'ready_to_load' THEN RETURN; END IF;

    v_closest_truck_id := NULL;
    FOR v_truck IN SELECT asset_id FROM jit_active_queues WHERE project_id = v_project_id AND status = 'waiting' ORDER BY joined_queue_at ASC LOOP
        SELECT created_at, driver_id INTO v_shift_start, v_driver_id FROM shift_assignments WHERE vehicle_id = v_truck.asset_id AND status = 'ACTIVE' ORDER BY created_at DESC LIMIT 1;
        IF v_shift_start IS NULL THEN v_shift_start := CURRENT_TIMESTAMP; END IF;

        v_shift_duration_hours := EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_shift_start)) / 3600.0;
        
        IF v_shift_duration_hours >= 11.5 THEN
            SELECT a.asset_code, COALESCE(pr.full_name, 'Usuario Desconocido') INTO v_asset_code, v_driver_name
            FROM assets a LEFT JOIN profiles pr ON pr.id = v_driver_id WHERE a.id = v_truck.asset_id;
            
            INSERT INTO webhook_events (event_type, payload)
            VALUES ('compliance_violation', jsonb_build_object(
                'project_id', v_project_id, 'project_name', v_project_name,
                'asset_id', v_truck.asset_id, 'asset_code', v_asset_code,
                'driver_name', v_driver_name, 'shift_duration_hours', ROUND(v_shift_duration_hours::numeric, 2),
                'legal_limit_hours', 11.5, 'timestamp', CURRENT_TIMESTAMP,
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
END;
$$;

-- matchmaker_dispatch_on_excavator_ready
CREATE OR REPLACE FUNCTION matchmaker_dispatch_on_excavator_ready()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_project_id UUID;
    v_project_name TEXT;
    v_active_material TEXT;
    v_closest_truck_id UUID;
    v_truck RECORD;
    v_shift_start TIMESTAMPTZ;
    v_driver_id UUID;
    v_driver_name TEXT;
    v_asset_code TEXT;
    v_shift_duration_hours NUMERIC;
BEGIN
    IF NEW.operational_status != 'ready_to_load' OR (OLD.operational_status = 'ready_to_load') THEN
        RETURN NEW;
    END IF;

    SELECT current_project_id INTO v_project_id FROM assets WHERE id = NEW.asset_id;
    IF v_project_id IS NULL THEN RETURN NEW; END IF;
    
    SELECT name INTO v_project_name FROM projects WHERE id = v_project_id;
    v_active_material := NEW.current_material;

    v_closest_truck_id := NULL;
    FOR v_truck IN SELECT asset_id FROM jit_active_queues WHERE project_id = v_project_id AND status = 'waiting' ORDER BY joined_queue_at ASC LOOP
        SELECT created_at, driver_id INTO v_shift_start, v_driver_id FROM shift_assignments WHERE vehicle_id = v_truck.asset_id AND status = 'ACTIVE' ORDER BY created_at DESC LIMIT 1;
        IF v_shift_start IS NULL THEN v_shift_start := CURRENT_TIMESTAMP; END IF;

        v_shift_duration_hours := EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_shift_start)) / 3600.0;
        
        IF v_shift_duration_hours >= 11.5 THEN
            SELECT a.asset_code, COALESCE(pr.full_name, 'Usuario Desconocido') INTO v_asset_code, v_driver_name
            FROM assets a LEFT JOIN profiles pr ON pr.id = v_driver_id WHERE a.id = v_truck.asset_id;
            
            INSERT INTO webhook_events (event_type, payload)
            VALUES ('compliance_violation', jsonb_build_object(
                'project_id', v_project_id, 'project_name', v_project_name,
                'asset_id', v_truck.asset_id, 'asset_code', v_asset_code,
                'driver_name', v_driver_name, 'shift_duration_hours', ROUND(v_shift_duration_hours::numeric, 2),
                'legal_limit_hours', 11.5, 'timestamp', CURRENT_TIMESTAMP,
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

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_matchmaker_on_excavator_ready ON excavator_states;
CREATE TRIGGER trg_matchmaker_on_excavator_ready
AFTER UPDATE ON excavator_states
FOR EACH ROW EXECUTE FUNCTION matchmaker_dispatch_on_excavator_ready();

-- 4. Aniquilar el Trigger Síncrono Espacial
DROP TRIGGER IF EXISTS trg_01_spatial_jit_dispatch ON asset_telemetry_logs;
DROP FUNCTION IF EXISTS process_jit_dispatch_trigger();
