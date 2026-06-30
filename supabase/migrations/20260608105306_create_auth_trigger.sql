-- 1. Función que construye el perfil y asigna el rol inicial
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- Insertamos el ID idéntico de Auth y asignamos el rol de Manager por defecto
  -- El fleet_id se genera automáticamente por el DEFAULT gen_random_uuid() de la tabla
  INSERT INTO public.profiles (id, role, full_name)
  VALUES (
    NEW.id, 
    'FLEET_MANAGER', 
    NEW.raw_user_meta_data->>'full_name'
  );
  RETURN NEW;
END;
$$;

-- 2. El Trigger que vigila permanentemente el sistema de Auth
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
