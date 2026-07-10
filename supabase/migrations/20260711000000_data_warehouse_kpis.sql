-- 20260711000000_data_warehouse_kpis.sql
-- Migración para el Data Warehouse y Agregación de KPIs

SET search_path = public, postgis;

-- 1. Añadir el bloque geológico a los ciclos de carga
ALTER TABLE load_cycles ADD COLUMN IF NOT EXISTS geological_block TEXT;

-- 2. Modificar funciones RPC de JIT para heredar el geological_block
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
    v_active_block TEXT;
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
    SELECT operational_status, current_material, geological_block INTO v_excavator_status, v_active_material, v_active_block
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
        INSERT INTO load_cycles (project_id, asset_id, status, material_type, geological_block, loading_started_at) 
        VALUES (v_project_id, v_closest_truck_id, 'loading', v_active_material, v_active_block, CURRENT_TIMESTAMP);
        PERFORM pg_notify('pgrst', jsonb_build_object('table', 'assets', 'action', 'broadcast', 'channel', 'jit_dispatch_' || v_closest_truck_id::TEXT, 'payload', jsonb_build_object('message', 'Atención. Proceda al cargadero principal de inmediato. Excavadora libre.'))::TEXT);
        INSERT INTO webhook_events (event_type, payload) VALUES ('jit_dispatch', jsonb_build_object('project_id', v_project_id, 'asset_id', v_closest_truck_id));
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION matchmaker_dispatch_on_excavator_ready()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_project_id UUID;
    v_project_name TEXT;
    v_active_material TEXT;
    v_active_block TEXT;
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
    v_active_block := NEW.geological_block;

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
        INSERT INTO load_cycles (project_id, asset_id, status, material_type, geological_block, loading_started_at) 
        VALUES (v_project_id, v_closest_truck_id, 'loading', v_active_material, v_active_block, CURRENT_TIMESTAMP);
        PERFORM pg_notify('pgrst', jsonb_build_object('table', 'assets', 'action', 'broadcast', 'channel', 'jit_dispatch_' || v_closest_truck_id::TEXT, 'payload', jsonb_build_object('message', 'Atención. Proceda al cargadero principal de inmediato. Excavadora libre.'))::TEXT);
        INSERT INTO webhook_events (event_type, payload) VALUES ('jit_dispatch', jsonb_build_object('project_id', v_project_id, 'asset_id', v_closest_truck_id));
    END IF;

    RETURN NEW;
END;
$$;

-- 3. Crear Vistas Materializadas

-- mv_daily_cycle_efficiency
CREATE MATERIALIZED VIEW mv_daily_cycle_efficiency AS
SELECT 
    project_id,
    DATE(loading_started_at) AS date,
    asset_id,
    COUNT(id) as total_cycles,
    AVG(EXTRACT(EPOCH FROM (transit_started_at - loading_started_at)) / 60.0) AS avg_loading_minutes
FROM load_cycles
WHERE transit_started_at IS NOT NULL
GROUP BY project_id, DATE(loading_started_at), asset_id;

CREATE UNIQUE INDEX idx_mv_daily_cycle_efficiency ON mv_daily_cycle_efficiency (project_id, date, asset_id);

-- mv_daily_production_tonnage
CREATE MATERIALIZED VIEW mv_daily_production_tonnage AS
SELECT 
    project_id,
    DATE(loading_started_at) AS date,
    material_type,
    COALESCE(geological_block, 'UNKNOWN') as geological_block,
    SUM(net_weight) AS total_net_weight,
    COUNT(id) as total_loads
FROM load_cycles
WHERE net_weight IS NOT NULL
GROUP BY project_id, DATE(loading_started_at), material_type, COALESCE(geological_block, 'UNKNOWN');

CREATE UNIQUE INDEX idx_mv_daily_production_tonnage ON mv_daily_production_tonnage (project_id, date, material_type, geological_block);

-- mv_daily_fleet_downtime
CREATE MATERIALIZED VIEW mv_daily_fleet_downtime AS
SELECT 
    project_id,
    DATE(reported_at) AS date,
    asset_id,
    SUM(EXTRACT(EPOCH FROM (COALESCE(rectified_at, CURRENT_TIMESTAMP) - reported_at)) / 3600.0) AS total_downtime_hours,
    COUNT(id) as total_defects
FROM plant_defects
GROUP BY project_id, DATE(reported_at), asset_id;

CREATE UNIQUE INDEX idx_mv_daily_fleet_downtime ON mv_daily_fleet_downtime (project_id, date, asset_id);

-- 4. Función de Refresco Concurrente
CREATE OR REPLACE FUNCTION refresh_managerial_kpis()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_cycle_efficiency;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_production_tonnage;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_fleet_downtime;
END;
$$;

-- 5. Programar pg_cron cada 15 minutos
-- Habilitar extensión si el superusuario lo permite (en Supabase cloud pg_cron suele estar habilitado)
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule('refresh_kpis', '*/15 * * * *', 'SELECT refresh_managerial_kpis()');
