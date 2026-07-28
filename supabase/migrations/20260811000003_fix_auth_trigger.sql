-- ============================================================================
-- MIGRACIÓN: REVERSIÓN DEL TRIGGER A ZERO-TRUST EN PRODUCCIÓN
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- Insertamos el ID idéntico de Auth y asignamos el rol 'driver' de forma determinista.
  -- Exigimos innegociablemente el fleet_id desde los metadatos de la invitación.
  INSERT INTO public.profiles (id, role, full_name, fleet_id)
  VALUES (
    NEW.id, 
    'driver', 
    NEW.raw_user_meta_data->>'full_name',
    (NEW.raw_user_meta_data->>'fleet_id')::uuid
  );
  RETURN NEW;
END;
$$;

COMMIT;
