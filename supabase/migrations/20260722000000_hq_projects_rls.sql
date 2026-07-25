-- Migration: 20260722000000_hq_projects_rls.sql
-- Inyección de doctrina: La autoridad global (super_admin, fleet_manager) 
-- debe tener visibilidad y control incondicional sobre la tabla de proyectos,
-- puenteando la barrera forense de project_members.

-- Permitir a los roles de cuartel general hacer SELECT incondicional
CREATE POLICY "HQ_global_select_projects" ON projects
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.id = auth.uid()
            AND profiles.role IN ('super_admin', 'fleet_manager')
        )
    );

-- Permitir a los roles de cuartel general hacer INSERT, UPDATE, DELETE incondicional
CREATE POLICY "HQ_global_mutate_projects" ON projects
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.id = auth.uid()
            AND profiles.role IN ('super_admin', 'fleet_manager')
        )
    );
