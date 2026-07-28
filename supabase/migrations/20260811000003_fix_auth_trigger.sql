-- ============================================================================
-- MIGRACIÓN: PARCHE BULLETPROOF PARA TRIGGER DE AUTENTICACIÓN
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_fleet_id UUID;
BEGIN
  -- Intentar obtener la flota desde los metadatos (como lo hace el Frontend)
  v_fleet_id := (NEW.raw_user_meta_data->>'fleet_id')::uuid;
  
  -- PARCHE: Si se está creando el usuario manualmente desde el panel de Supabase (UI),
  -- los metadatos vienen vacíos. Asignamos a la fuerza la flota de Hobart.
  IF v_fleet_id IS NULL THEN
     v_fleet_id := 'f1ee7000-0000-4000-8000-000000000001'::uuid;
  END IF;

  INSERT INTO public.profiles (id, role, full_name, fleet_id)
  VALUES (
    NEW.id, 
    'account_owner', 
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'Thomas Shelby'),
    v_fleet_id
  );
  RETURN NEW;
END;
$$;

COMMIT;
