-- =========================================================================
-- JITSite Core: Live Fleet Analytical View
-- =========================================================================

-- Vista dinámica que computa el estado efectivo (Caducidad de Telemetría)
-- Evita mutaciones redundantes de CRON y protege la facturación.
CREATE OR REPLACE VIEW live_fleet_status AS
SELECT 
    id,
    fleet_manager_id,
    current_project_id,
    last_known_location,
    last_telemetry_timestamp,
    status AS raw_status,
    CASE 
        WHEN last_telemetry_timestamp IS NULL THEN 'unknown'
        WHEN NOW() - last_telemetry_timestamp > INTERVAL '2 minutes' THEN 'offline'
        ELSE status 
    END AS effective_status
FROM assets;
