BEGIN;

ALTER TABLE public.assets 
ALTER COLUMN current_engine_hours SET DEFAULT 0,
ALTER COLUMN current_odometer SET DEFAULT 0;

COMMIT;
