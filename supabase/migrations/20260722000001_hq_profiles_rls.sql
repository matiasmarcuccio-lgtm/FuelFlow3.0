-- Permitir a los roles de cuartel general hacer SELECT de todos los perfiles
CREATE POLICY "HQ_global_select_profiles" ON profiles
    FOR SELECT USING (
        (SELECT role FROM profiles WHERE id = auth.uid()) IN ('super_admin', 'fleet_manager')
    );

-- Permitir a los roles de cuartel general actualizar perfiles (para cambiar roles, etc. aunque usamos RPC, nunca está de más para otras gestiones)
CREATE POLICY "HQ_global_update_profiles" ON profiles
    FOR UPDATE USING (
        (SELECT role FROM profiles WHERE id = auth.uid()) IN ('super_admin', 'fleet_manager')
    );
