-- FASE 3: MOTOR DE BÚSQUEDA FORENSE (Audit)
-- Regla de Negocio: La auditoría reconstruye la línea de vida de una carga en O(log N)

CREATE OR REPLACE FUNCTION get_offer_chronology(offer_uuid UUID)
RETURNS SETOF access_logs AS $$
BEGIN
    RETURN QUERY
    SELECT al.* 
    FROM access_logs al
    WHERE 
        (al.table_name = 'load_offers' AND al.row_id = offer_uuid)
        OR 
        (al.table_name = 'cor_manifests' AND al.row_id IN (
            SELECT id FROM cor_manifests WHERE load_offer_id = offer_uuid
        ))
        OR 
        (al.table_name = 'structural_elements' AND al.row_id IN (
            SELECT id FROM structural_elements WHERE load_offer_id = offer_uuid
        ))
    ORDER BY al.timestamp DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Aseguramos que la RPC solo sea ejecutable por usuarios autenticados y con rol admin 
-- (el RLS de access_logs ya bloquea select para no-admins, pero blindamos el execute de todas formas,
-- aunque en este caso SECURITY DEFINER se salta el RLS si no aplicamos el filtro explícito.
-- ¡CORRECCIÓN ZERO-TRUST!: Si usamos SECURITY DEFINER, la función corre como Postgres, evadiendo el RLS de access_logs.
-- Para respetar la física del RLS, debemos usar SECURITY INVOKER.

DROP FUNCTION IF EXISTS get_offer_chronology(UUID);

CREATE OR REPLACE FUNCTION get_offer_chronology(offer_uuid UUID)
RETURNS SETOF access_logs AS $$
BEGIN
    RETURN QUERY
    SELECT al.* 
    FROM access_logs al
    WHERE 
        (al.table_name = 'load_offers' AND al.row_id = offer_uuid)
        OR 
        (al.table_name = 'cor_manifests' AND al.row_id IN (
            SELECT id FROM cor_manifests WHERE load_offer_id = offer_uuid
        ))
        OR 
        (al.table_name = 'structural_elements' AND al.row_id IN (
            SELECT id FROM structural_elements WHERE load_offer_id = offer_uuid
        ))
    ORDER BY al.timestamp DESC;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER; -- Usar SECURITY INVOKER respeta el RLS de access_logs
