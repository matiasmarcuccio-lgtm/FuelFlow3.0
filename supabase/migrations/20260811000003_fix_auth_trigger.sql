-- ============================================================================
-- MIGRACIÓN: CORRECCIÓN DEL TRIGGER DE AUTENTICACIÓN
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- Insertamos el ID idéntico de Auth y asignamos el rol de Manager por defecto (en minúsculas para respetar el constraint)
  INSERT INTO public.profiles (id, role, full_name)
  VALUES (
    NEW.id, 
    'fleet_manager', 
    NEW.raw_user_meta_data->>'full_name'
  );
  RETURN NEW;
END;
$$;

COMMIT;
