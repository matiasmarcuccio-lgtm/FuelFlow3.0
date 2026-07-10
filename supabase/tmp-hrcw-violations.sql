-- 1. Vista Táctica para el Motor de Automatización (n8n / Make)
-- Pre-filtra exclusivamente a los activos "Nodos Muertos" que quedaron aparcados dentro de una zona HRCW
CREATE OR REPLACE VIEW hrcw_dead_node_violations AS
SELECT 
    v.id AS asset_id,
    v.fleet_manager_id,
    v.current_project_id,
    v.last_known_location,
    v.last_telemetry_timestamp,
    p.name AS project_name
FROM live_fleet_status v
JOIN projects p ON v.current_project_id = p.id
WHERE 
    v.effective_status = 'offline'
    AND v.last_known_location->>'lng' IS NOT NULL
    AND v.last_known_location->>'lat' IS NOT NULL
    AND p.hrcw_polygon IS NOT NULL
    AND ST_Intersects(
        ST_SetSRID(ST_MakePoint((v.last_known_location->>'lng')::numeric, (v.last_known_location->>'lat')::numeric), 4326),
        p.hrcw_polygon
    );
