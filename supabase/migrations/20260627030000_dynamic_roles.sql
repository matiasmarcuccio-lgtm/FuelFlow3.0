-- 1. Añadir columna de verificación administrativa al perfil
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT false;

-- 2. Reescribir el trigger de autenticación con seguridad de lista blanca
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  requested_role text;
  assigned_role text := 'GUEST'; -- Rol de cuarentena por defecto en caso de inyección maliciosa
BEGIN
  -- Extraer el rol solicitado
  requested_role := NEW.raw_user_meta_data->>'role';

  -- Filtro de Seguridad (Lista Blanca)
  IF requested_role IN ('DRIVER_ABN', 'DRIVER_TFN', 'FLEET_MANAGER', 'BUILDER', 'INSPECTOR') THEN
    assigned_role := requested_role;
  END IF;

  -- Insertar el perfil inicializando is_verified en false explícitamente para el escrutinio de CoR
  INSERT INTO public.profiles (id, role, full_name, is_verified)
  VALUES (
    NEW.id, 
    assigned_role, 
    NEW.raw_user_meta_data->>'full_name',
    false
  );
  
  RETURN NEW;
END;
$$;
