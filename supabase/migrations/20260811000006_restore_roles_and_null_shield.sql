-- ============================================================================
-- CIRUGÍA FORENSE CAPA 0: RESTAURACIÓN DE ROLES Y BLINDAJE DE NULIDAD
-- ============================================================================
BEGIN;

-- 1. Resucitar roles operativos y administrativos en la lista blanca de la base de datos viva
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check 
CHECK (role IN ('super_admin', 'fleet_manager', 'fitter', 'driver', 'account_owner', 'pending_onboarding', 'dispatcher', 'supervisor', 'suspended'));

-- 2. Actualizar la restricción de nulidad para permitir que los usuarios suspendidos carezcan de flota
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS chk_profiles_fleet_id_not_null;
ALTER TABLE public.profiles ADD CONSTRAINT chk_profiles_fleet_id_not_null
CHECK (
    (role IN ('pending_onboarding', 'super_admin', 'suspended')) OR (fleet_id IS NOT NULL)
);

-- 3. Notificar a PostgREST para recargar la caché de esquema al instante
NOTIFY pgrst, 'reload schema';

COMMIT;
