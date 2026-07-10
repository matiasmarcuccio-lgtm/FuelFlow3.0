-- =========================================================================
-- JITSite Core: Transactional Matching Engine & Orchestration Bridge
-- =========================================================================

-- 1. El Sumidero de Eventos (Webhook Outbox Pattern)
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(50) DEFAULT 'pending'
);

ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

-- Activar Realtime para que n8n pueda suscribirse vía WebSockets
ALTER PUBLICATION supabase_realtime ADD TABLE webhook_events;

-- 2. La Topología de la Cola (JIT Queue State)
CREATE TABLE IF NOT EXISTS public.jit_active_queues (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES public.assets(id) ON DELETE CASCADE,
    joined_queue_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(50) DEFAULT 'waiting', -- 'waiting', 'dispatched'
    UNIQUE(project_id, asset_id, status)
);

ALTER TABLE public.jit_active_queues ENABLE ROW LEVEL SECURITY;

-- 3. El Matchmaker Trigger (Reemplazo del trigger cinemático primitivo)

-- Asegurar orden de ejecución (01 va antes que trg_project_asset_telemetry)
DROP TRIGGER IF EXISTS trigger_spatial_jit_dispatch ON asset_telemetry_logs;
DROP TRIGGER IF EXISTS trg_01_spatial_jit_dispatch ON asset_telemetry_logs;

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

        RAISE LOG 'v_was_inside: %, v_is_inside_strict: %, v_is_inside_buffered: %', v_was_inside, v_is_inside_strict, v_is_inside_buffered;

        -- Condición Entrada: Entra al pad estricto y no está en la cola
        IF NOT v_was_inside AND v_is_inside_strict THEN
            INSERT INTO jit_active_queues (project_id, asset_id, status)
            VALUES (v_project_id, NEW.asset_id, 'waiting')
            ON CONFLICT (project_id, asset_id, status) DO NOTHING;
        END IF;

        -- Condición Salida: Sale del pad holgado (libera el espacio)
        IF v_was_inside AND NOT v_is_inside_buffered THEN
            -- Eliminarlo de la cola activa si estaba
            DELETE FROM jit_active_queues WHERE asset_id = NEW.asset_id AND status = 'waiting';

            -- MATCHMAKER: Disparar asignación al camión más antiguo de la cola (FIFO)
            SELECT asset_id INTO v_closest_truck_id
            FROM jit_active_queues
            WHERE project_id = v_project_id AND status = 'waiting'
            ORDER BY joined_queue_at ASC
            LIMIT 1;

            IF v_closest_truck_id IS NOT NULL THEN
                UPDATE jit_active_queues SET status = 'dispatched' WHERE asset_id = v_closest_truck_id;
                
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

CREATE TRIGGER trg_01_spatial_jit_dispatch
    AFTER INSERT ON asset_telemetry_logs
    FOR EACH ROW
    EXECUTE FUNCTION process_jit_dispatch_trigger();

-- 4. El Barrido Temporal (Temporal Sweeper) para Estancamientos
CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE OR REPLACE FUNCTION sweep_stagnant_queues()
RETURNS void 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_stagnant RECORD;
BEGIN
    FOR v_stagnant IN 
        SELECT id, project_id, asset_id, joined_queue_at 
        FROM jit_active_queues 
        WHERE status = 'waiting' 
          AND (CURRENT_TIMESTAMP - joined_queue_at) > interval '15 minutes'
          AND NOT EXISTS (
              SELECT 1 FROM webhook_events 
              WHERE event_type = 'queue_stagnation' 
                AND payload->>'asset_id' = jit_active_queues.asset_id::TEXT
                AND created_at > (CURRENT_TIMESTAMP - interval '1 hour') -- No spamear
          )
    LOOP
        -- Empujar alerta al sumidero para n8n
        INSERT INTO webhook_events (event_type, payload)
        VALUES ('queue_stagnation', jsonb_build_object(
            'project_id', v_stagnant.project_id, 
            'asset_id', v_stagnant.asset_id,
            'wait_time_minutes', EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_stagnant.joined_queue_at)) / 60
        ));
    END LOOP;
END;
$$;

-- Agendar el barrido para ejecutarse cada minuto
-- Nota: La extension pg_cron requiere configuración de postgresql.conf en entornos autogestionados, pero en Supabase funciona nativamente para roles con permisos.
SELECT cron.schedule('sweep_jit_queues', '* * * * *', 'SELECT sweep_stagnant_queues();');
