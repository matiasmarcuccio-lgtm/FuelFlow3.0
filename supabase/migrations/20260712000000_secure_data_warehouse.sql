-- 20260712000000_secure_data_warehouse.sql
-- Migración para blindar las Vistas Materializadas con Vistas Seguras RLS (Layer 0.75)

SET search_path = public, postgis;

-- 1. Aislar las vistas materializadas del acceso web público
REVOKE ALL ON mv_daily_cycle_efficiency FROM PUBLIC;
REVOKE ALL ON mv_daily_cycle_efficiency FROM authenticated;
REVOKE ALL ON mv_daily_cycle_efficiency FROM anon;

REVOKE ALL ON mv_daily_production_tonnage FROM PUBLIC;
REVOKE ALL ON mv_daily_production_tonnage FROM authenticated;
REVOKE ALL ON mv_daily_production_tonnage FROM anon;

REVOKE ALL ON mv_daily_fleet_downtime FROM PUBLIC;
REVOKE ALL ON mv_daily_fleet_downtime FROM authenticated;
REVOKE ALL ON mv_daily_fleet_downtime FROM anon;

-- 2. Construir las fachadas seguras (Secure Views) con herencia RLS implícita
-- Nota: En lugar de hacer una subconsulta completa, hacemos un JOIN o un IN sobre project_members
-- Esto garantiza que PostgREST parsee correctamente los filtros REST de fechas sin comprometer la seguridad.

CREATE OR REPLACE VIEW secure_daily_cycle_efficiency AS
SELECT * FROM mv_daily_cycle_efficiency
WHERE project_id IN (
    SELECT project_id FROM project_members WHERE user_id = auth.uid()
);

CREATE OR REPLACE VIEW secure_daily_production_tonnage AS
SELECT * FROM mv_daily_production_tonnage
WHERE project_id IN (
    SELECT project_id FROM project_members WHERE user_id = auth.uid()
);

CREATE OR REPLACE VIEW secure_daily_fleet_downtime AS
SELECT * FROM mv_daily_fleet_downtime
WHERE project_id IN (
    SELECT project_id FROM project_members WHERE user_id = auth.uid()
);

-- 3. Otorgar permisos de lectura únicamente sobre las vistas seguras a los usuarios autenticados
GRANT SELECT ON secure_daily_cycle_efficiency TO authenticated;
GRANT SELECT ON secure_daily_production_tonnage TO authenticated;
GRANT SELECT ON secure_daily_fleet_downtime TO authenticated;

