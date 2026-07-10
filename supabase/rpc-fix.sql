-- 1. Destruir la vista vulnerable
DROP VIEW IF EXISTS business_metrics;

-- 2. Crear la función RPC segura
CREATE OR REPLACE FUNCTION get_admin_business_metrics()
RETURNS TABLE (
    active_users BIGINT,
    active_projects BIGINT,
    projected_mrr BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER -- Salta RLS temporalmente para calcular métricas globales
SET search_path = public -- Mitiga riesgos de inyección en el search_path
AS $$
BEGIN
    -- Validación dura: Si el usuario no es Super Admin, abortar instantáneamente
    IF (SELECT role FROM profiles WHERE id = auth.uid()) != 'super_admin' THEN
        RAISE EXCEPTION 'Access Denied: Super Admin privileges required.';
    END IF;

    -- Retornar métricas globales con subconsultas limpias (sin producto cartesiano)
    RETURN QUERY
    SELECT
        (SELECT COUNT(DISTINCT id) FROM profiles)::BIGINT AS active_users,
        (SELECT COUNT(DISTINCT id) FROM projects WHERE status = 'active')::BIGINT AS active_projects,
        (SELECT COALESCE(SUM(CASE WHEN project_type = 'long_term' THEN 500 ELSE 1500 END), 0) FROM projects)::BIGINT AS projected_mrr;
END;
$$;
