-- Expansión de la restricción de roles para invitaciones
ALTER TABLE "public"."fleet_invites" DROP CONSTRAINT IF EXISTS "fleet_invites_role_check";
ALTER TABLE "public"."fleet_invites" ADD CONSTRAINT "fleet_invites_role_check" 
CHECK (("role")::"text" = ANY ((ARRAY['driver'::character varying, 'fitter'::character varying, 'supervisor'::character varying, 'fleet_manager'::character varying, 'dispatcher'::character varying])::"text"[]));

-- Actualización de la política de seguridad RLS (Zero-Trust) para creación de invitaciones
DROP POLICY IF EXISTS "Fleet Managers pueden crear invitaciones" ON "public"."fleet_invites";

CREATE POLICY "Managers and Owners can create invites" ON "public"."fleet_invites"
FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = created_by 
  AND fleet_id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid()) 
  AND (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('account_owner', 'fleet_manager')
);

-- Actualización de la política RLS para lectura de invitaciones
DROP POLICY IF EXISTS "Fleet Managers pueden ver sus invitaciones" ON "public"."fleet_invites";

CREATE POLICY "Managers and Owners can view their fleet invites" ON "public"."fleet_invites"
FOR SELECT TO authenticated
USING (
  fleet_id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid())
  AND (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('account_owner', 'fleet_manager')
);
