-- Actualización del trigger para forzar Zero-Trust en el registro público.
-- Ignoramos deliberadamente el raw_user_meta_data para el rol, evitando inyecciones.
-- Todo nuevo usuario entra como 'driver' (nivel más bajo) de forma innegociable.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- Insertamos el ID idéntico de Auth y asignamos el rol 'driver' de forma determinista.
  -- El full_name sí se extrae del metadata ya que es inofensivo operativamente.
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
