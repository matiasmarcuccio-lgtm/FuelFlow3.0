-- =========================================================================
-- JITSite Core: HRCW Dead Node Violations View
-- =========================================================================

-- Vista Táctica para el Motor de Automatización (n8n / Make)
-- Pre-filtra exclusivamente a los activos "Nodos Muertos" que quedaron aparcados dentro de una zona HRCW
-- Excluye cierres de turno legítimos para evitar fatiga de alertas.
CREATE OR REPLACE VIEW hrcw_dead_node_violations AS
SELECT 
    f.id AS asset_id,
    f.current_project_id,
    f.last_known_location,
    f.last_telemetry_timestamp,
    -- Extraer el último tipo de evento registrado directamente del libro mayor
    (SELECT event_type FROM asset_telemetry_logs 
     WHERE asset_id = f.id 
     ORDER BY client_timestamp DESC LIMIT 1) AS last_event_type
FROM live_fleet_status f
WHERE f.effective_status = 'offline'
  -- El filtro crítico: Solo alertar si el último suspiro de la máquina NO fue un apagado voluntario
  AND (
      SELECT event_type FROM asset_telemetry_logs 
      WHERE asset_id = f.id 
      ORDER BY client_timestamp DESC LIMIT 1
  ) NOT IN ('graceful_shutdown', 'operator_checkout')
  -- Intersección espacial PostGIS pura contra el polígono del proyecto
  AND ST_Intersects(
      (SELECT hrcw_polygon FROM projects WHERE id = f.current_project_id),
      ST_SetSRID(
          ST_MakePoint(
              (f.last_known_location->>'lng')::NUMERIC, 
              (f.last_known_location->>'lat')::NUMERIC
          ), 
          4326
      )
  );
