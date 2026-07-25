CREATE OR REPLACE VIEW public.view_fleet_matrix AS
SELECT 
    id AS vehicle_id, 
    internal_code AS registration_number,
    status
FROM public.assets;
