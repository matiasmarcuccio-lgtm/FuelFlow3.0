CREATE OR REPLACE VIEW public.view_fleet_matrix AS
SELECT 
    id AS vehicle_id, 
    internal_code AS registration_number,
    status
FROM public.assets;

-- Dar permisos básicos para que se pueda leer por usuarios autenticados
GRANT SELECT ON public.view_fleet_matrix TO authenticated;
