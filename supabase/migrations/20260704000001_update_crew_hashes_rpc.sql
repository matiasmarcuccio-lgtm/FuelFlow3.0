CREATE OR REPLACE FUNCTION get_project_crew_hashes(p_project_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, postgis
AS $$
DECLARE
    v_topology JSONB;
    v_crew_roster JSONB;
BEGIN
    -- 1. Validar permisos de acceso
    IF NOT EXISTS (
        SELECT 1 FROM project_members
        WHERE project_members.project_id = p_project_id
        AND project_members.user_id = auth.uid()
        AND project_members.role IN ('supervisor', 'fleet_manager')
    ) THEN
        RAISE EXCEPTION 'Access Denied: You are not authorized to sync this project.';
    END IF;

    -- 2. Empaquetar la topología completa con casteo estricto a JSONB
    SELECT jsonb_build_object(
        'hrcw_polygon', ST_AsGeoJSON(hrcw_polygon)::JSONB,
        'loading_pad_strict', ST_AsGeoJSON(loading_pad_geometry)::JSONB,
        'loading_pad_buffered', ST_AsGeoJSON(loading_pad_buffered)::JSONB
    ) INTO v_topology
    FROM projects
    WHERE id = p_project_id;

    -- 3. Extraer las identidades criptográficas de la cuadrilla
    SELECT jsonb_agg(
        jsonb_build_object(
            'user_id', p.id,
            'full_name', p.full_name,
            'pin_hash', p.operational_pin_hash,
            'pin_salt', p.operational_pin_salt
        )
    ) INTO v_crew_roster
    FROM profiles p
    JOIN project_members pm ON p.id = pm.user_id
    WHERE pm.project_id = p_project_id;

    -- 4. Retornar el payload unificado y jerárquico
    RETURN jsonb_build_object(
        'topology', v_topology,
        'crew', v_crew_roster
    );
END;
$$;
