-- 1. Habilitar la extensión espacial PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;

-- 2. Añadir columnas de geometría estricta 2D EPSG:4326 a la tabla de ofertas de carga
ALTER TABLE public.load_offers 
  ADD COLUMN IF NOT EXISTS staging_area GEOMETRY(Polygon, 4326),
  ADD COLUMN IF NOT EXISTS active_excavation GEOMETRY(Polygon, 4326),
  ADD COLUMN IF NOT EXISTS exclusion_zone GEOMETRY(Polygon, 4326);

-- 3. Crear el RPC (Remote Procedure Call) seguro para inyectar la geometría GeoJSON
CREATE OR REPLACE FUNCTION public.update_project_geometry(
  p_project_id UUID,
  p_zone_type TEXT,
  p_geojson JSONB
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, postgis
AS $$
DECLARE
  v_geom GEOMETRY;
BEGIN
  -- 1. Convertir el objeto GeoJSON a una Geometría PostGIS pura
  -- ST_GeomFromGeoJSON lee automáticamente el CRS si está presente o asume 4326 si el GeoJSON cumple el estándar
  v_geom := ST_SetSRID(ST_GeomFromGeoJSON(p_geojson::text), 4326);

  -- 2. Inyección dinámica en la columna correspondiente
  IF p_zone_type = 'staging_area' THEN
    UPDATE public.load_offers SET staging_area = v_geom WHERE id = p_project_id;
  ELSIF p_zone_type = 'active_excavation' THEN
    UPDATE public.load_offers SET active_excavation = v_geom WHERE id = p_project_id;
  ELSIF p_zone_type = 'exclusion_zone' THEN
    UPDATE public.load_offers SET exclusion_zone = v_geom WHERE id = p_project_id;
  ELSE
    RAISE EXCEPTION 'Tipo de zona topográfica no reconocida: %', p_zone_type;
  END IF;

  -- Validar si el proyecto existía
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Proyecto UUID % no encontrado en el motor logístico', p_project_id;
  END IF;
END;
$$;
