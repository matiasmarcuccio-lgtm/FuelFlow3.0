-- 1. Añadir columnas criptográficas exclusivas para operaciones de campo
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS operational_pin_hash TEXT,
ADD COLUMN IF NOT EXISTS operational_pin_salt TEXT;

-- 2. Crear el RPC de sincronización de cuadrilla (Roster Sync)
CREATE OR REPLACE FUNCTION get_project_crew_hashes(p_project_id UUID)
RETURNS TABLE (
    user_id UUID,
    full_name TEXT,
    pin_hash TEXT,
    pin_salt TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM project_members
        WHERE project_members.project_id = p_project_id
        AND project_members.user_id = auth.uid()
        AND project_members.role IN ('supervisor', 'fleet_manager')
    ) THEN
        RAISE EXCEPTION 'Access Denied: You are not authorized to sync this crew roster.';
    END IF;

    RETURN QUERY
    SELECT
        p.id,
        p.full_name,
        p.operational_pin_hash,
        p.operational_pin_salt
    FROM profiles p
    JOIN project_members pm ON p.id = pm.user_id
    WHERE pm.project_id = p_project_id;
END;
$$;
