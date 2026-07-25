-- Arreglar la llave foránea incorrecta en fleet_invites
ALTER TABLE public.fleet_invites
DROP CONSTRAINT IF EXISTS fleet_invites_fleet_id_fkey;

ALTER TABLE public.fleet_invites
ADD CONSTRAINT fleet_invites_fleet_id_fkey 
FOREIGN KEY (fleet_id) REFERENCES public.fleets(id) ON DELETE CASCADE;

-- Refrescar la caché de esquema de PostgREST
NOTIFY pgrst, 'reload schema';
