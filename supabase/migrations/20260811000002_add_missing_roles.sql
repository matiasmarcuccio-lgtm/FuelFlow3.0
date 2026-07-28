-- ============================================================================
-- MIGRACIÓN: ALINEACIÓN DE ROLES (ACCOUNT_OWNER Y DISPATCHER)
-- ============================================================================
BEGIN;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check CHECK (role IN ('super_admin', 'account_owner', 'fleet_manager', 'dispatcher', 'supervisor', 'driver', 'suspended', 'fitter'));

-- Forzar recarga de esquema
NOTIFY pgrst, 'reload schema';

COMMIT;
