-- 1. Actualización de la política principal de Despacho (asset_assignments)
DROP POLICY IF EXISTS "Enforce JWT Financial Lockdown on Dispatch" ON public.asset_assignments;

CREATE POLICY "Enforce JWT Financial Lockdown on Dispatch" ON public.asset_assignments
FOR ALL
USING (
    fleet_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'fleet_id')::uuid
    AND 
    (current_setting('request.jwt.claims', true)::jsonb ->> 'subscription_status') IN ('active', 'trialing')
    -- EL ESCUDO MULTIFACTOR: Exigimos AAL2 para roles con jurisdicción crítica
    AND (
        (current_setting('request.jwt.claims', true)::jsonb ->> 'user_role') NOT IN ('supervisor', 'fleet_manager', 'fitter')
        OR (auth.jwt()->>'aal') = 'aal2'
    )
);

-- 2. Asegurar también la Bóveda de Resolución (maintenance_logs)
DROP POLICY IF EXISTS "Workshop personnel can update logs" ON public.asset_lockouts;

CREATE POLICY "Workshop personnel can update logs" ON public.asset_lockouts
FOR UPDATE
USING (
    (current_setting('request.jwt.claims', true)::jsonb ->> 'user_role') IN ('fitter', 'fleet_manager', 'super_admin')
    -- MFA estricto para cerrar fallas mecánicas
    AND (auth.jwt()->>'aal') = 'aal2'
);
