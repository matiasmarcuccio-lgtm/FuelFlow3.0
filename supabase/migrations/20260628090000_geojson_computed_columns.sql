-- Migración: Columnas Computadas (Computed Columns) para GeoJSON
-- Permite que PostgREST sirva los polígonos nativamente como JSON puro sin coste de CPU en el cliente

CREATE OR REPLACE FUNCTION public.staging_area_geojson(offer public.load_offers)
RETURNS jsonb
LANGUAGE sql IMMUTABLE
AS $$
  SELECT ST_AsGeoJSON(offer.staging_area)::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.active_excavation_geojson(offer public.load_offers)
RETURNS jsonb
LANGUAGE sql IMMUTABLE
AS $$
  SELECT ST_AsGeoJSON(offer.active_excavation)::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.exclusion_zone_geojson(offer public.load_offers)
RETURNS jsonb
LANGUAGE sql IMMUTABLE
AS $$
  SELECT ST_AsGeoJSON(offer.exclusion_zone)::jsonb;
$$;
