-- =========================================================================
-- JITSite Core: Automated Spatial Matching Engine (JIT Dispatch)
-- =========================================================================

-- 1. Añadir la geometría del cargadero al proyecto (El origen del flujo)
ALTER TABLE projects 
ADD COLUMN IF NOT EXISTS loading_pad_geometry GEOMETRY(Polygon, 4326);

-- 2. Modificar la proyección de activos para evaluar eventos cinemáticos de despacho
CREATE OR REPLACE FUNCTION process_jit_dispatch_trigger()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, postgis
AS $$
DECLARE
    v_project_id UUID;
    v_loading_pad GEOMETRY;
    v_was_inside_pad BOOLEAN;
    v_is_inside_pad BOOLEAN;
    v_closest_truck_id UUID;
    v_dispatch_message TEXT;
BEGIN
    -- Extraer el proyecto actual del activo que emite telemetría
    SELECT current_project_id INTO v_project_id 
    FROM assets WHERE id = NEW.asset_id;
    
    IF v_project_id IS NULL THEN RETURN NEW; END IF;

    -- Obtener la geometría del cargadero de este proyecto
    SELECT loading_pad_geometry INTO v_loading_pad 
    FROM projects WHERE id = v_project_id;

    IF v_loading_pad IS NULL THEN RETURN NEW; END IF;

    -- Evaluar si el activo estaba y está dentro del cargadero basándose en el historial
    SELECT ST_Contains(v_loading_pad, ST_SetSRID(ST_MakePoint(
        (last_known_location->>'lng')::NUMERIC, 
        (last_known_location->>'lat')::NUMERIC
    ), 4326)) INTO v_was_inside_pad
    FROM assets WHERE id = NEW.asset_id;

    SELECT ST_Contains(v_loading_pad, ST_SetSRID(ST_MakePoint(
        (NEW.payload->>'location'->>'lng')::NUMERIC, 
        (NEW.payload->>'location'->>'lat')::NUMERIC
    ), 4326)) INTO v_is_inside_pad;

    -- [TRIGGER CINEMÁTICO]: El camión estaba cargando y acaba de salir del cargadero
    IF v_was_inside_pad AND NOT v_is_inside_pad AND (NEW.payload->>'category' = 'haul_truck') THEN
        
        -- Encontrar el camión 'idle' más cercano euclidianamente fuera del cargadero
        SELECT a.id INTO v_closest_truck_id
        FROM assets a
        WHERE a.current_project_id = v_project_id
          AND a.status = 'in_site'
          AND a.category = 'haul_truck'
          AND a.id != NEW.asset_id -- Excluir al que va saliendo
          AND NOT ST_Contains(v_loading_pad, ST_SetSRID(ST_MakePoint(
              (a.last_known_location->>'lng')::NUMERIC, 
              (a.last_known_location->>'lat')::NUMERIC
          ), 4326))
        ORDER BY ST_Distance(
            v_loading_pad,
            ST_SetSRID(ST_MakePoint(
                (a.last_known_location->>'lng')::NUMERIC, 
                (a.last_known_location->>'lat')::NUMERIC
            ), 4326)
        ) ASC
        LIMIT 1;

        -- Si hay un camión disponible en la zona de espera, emitir el despacho acústico inmediato
        IF v_closest_truck_id IS NOT NULL THEN
            v_dispatch_message := 'Atención. Proceda al cargadero principal de inmediato. Excavadora libre.';
            
            -- Inyectar el payload directo a la tabla de canales broadcast de Supabase Realtime
            PERFORM pg_notify(
                'pgrst',
                jsonb_build_object(
                    'table', 'assets',
                    'action', 'broadcast',
                    'channel', 'jit_dispatch_' || v_closest_truck_id::TEXT,
                    'payload', jsonb_build_object('message', v_dispatch_message)
                )::TEXT
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- 3. Anclar el procedimiento al libro mayor inmutable
DROP TRIGGER IF EXISTS trigger_spatial_jit_dispatch ON asset_telemetry_logs;
CREATE TRIGGER trigger_spatial_jit_dispatch
    AFTER INSERT ON asset_telemetry_logs
    FOR EACH ROW
    EXECUTE FUNCTION process_jit_dispatch_trigger();
