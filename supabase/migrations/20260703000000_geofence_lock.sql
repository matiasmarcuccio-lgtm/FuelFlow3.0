-- =========================================================================
-- JITSite Core: Geofencing Dinámico (PostGIS) y Watchdog MDM
-- =========================================================================

-- 1. Habilitar el motor espacial (Extensión oficial de Supabase)
CREATE EXTENSION IF NOT EXISTS postgis SCHEMA public;

-- 2. Inyectar la columna espacial con validación estricta de coordenadas WGS84
ALTER TABLE projects 
ADD COLUMN IF NOT EXISTS hrcw_polygon GEOMETRY(Polygon, 4326);

-- 3. Reescribir el RPC para empaquetar la topología junto a la cuadrilla
DROP FUNCTION IF EXISTS get_project_crew_hashes(UUID);

CREATE OR REPLACE FUNCTION get_project_crew_hashes(p_project_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, postgis
AS $$
DECLARE
    v_hrcw_geojson JSONB;
    v_crew_roster JSONB;
BEGIN
    -- Validar permisos de acceso
    IF NOT EXISTS (
        SELECT 1 FROM project_members
        WHERE project_members.project_id = p_project_id
        AND project_members.user_id = auth.uid()
        AND project_members.role IN ('supervisor', 'fleet_manager')
    ) THEN
        RAISE EXCEPTION 'Access Denied: You are not authorized to sync this project.';
    END IF;

    -- Extraer y castear el perímetro a GeoJSON ligero para el cliente
    SELECT ST_AsGeoJSON(hrcw_polygon)::JSONB INTO v_hrcw_geojson
    FROM projects
    WHERE id = p_project_id;

    -- Agregar las identidades criptográficas de la cuadrilla
    SELECT jsonb_agg(
        jsonb_build_object(
            'user_id', p.id,
            'full_name', p.full_name,
            'pin_hash', p.operational_pin_hash,
            'pin_salt', p.operational_pin_salt
        )
    ) INTO v_crew_roster
    FROM profiles p
    JOIN project_members pm ON p.id = pm.user_id
    WHERE pm.project_id = p_project_id;

    -- Retornar el payload unificado a TanStack Query
    RETURN jsonb_build_object(
        'hrcw_polygon', v_hrcw_geojson,
        'crew', v_crew_roster
    );
END;
$$;
