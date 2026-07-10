-- 1. Crear el libro mayor de excepciones (DLQ Real a nivel de datos)
CREATE TABLE IF NOT EXISTS telemetry_dead_letter_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID, -- Sin restricción FK rígida para asegurar que el dato corrupto se guarde
    recorded_by UUID,
    event_type TEXT,
    payload JSONB,
    client_timestamp TIMESTAMP WITH TIME ZONE,
    error_code TEXT,
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Asegurar RLS en la DLQ: Ningún operario puede leer ni alterar esto. 
-- Solo el Super Admin tiene acceso de lectura para auditoría forense.
ALTER TABLE telemetry_dead_letter_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dlq_super_admin_select_policy ON telemetry_dead_letter_logs;
CREATE POLICY dlq_super_admin_select_policy ON telemetry_dead_letter_logs
    FOR SELECT USING ((SELECT role FROM profiles WHERE id = auth.uid()) = 'super_admin');

-- 2. Modificar el conducto de ingesta para atrapar fallos estructurales
CREATE OR REPLACE FUNCTION submit_telemetry_event(
    p_asset_id UUID,
    p_recorded_by UUID,
    p_event_type TEXT,
    p_payload JSONB,
    p_client_timestamp TIMESTAMP WITH TIME ZONE
)
RETURNS TEXT -- Retorna 'SUCCESS' o el código de error manejado por el sistema
LANGUAGE plpgsql
SECURITY DEFINER -- Ejecuta con privilegios del sistema para escribir en la DLQ sin exponer la tabla al rol public
SET search_path = public
AS $$
BEGIN
    -- Validar autenticación básica antes de procesar cualquier dato
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated';
    END IF;

    -- Intentar la inserción en el libro mayor inmutable
    INSERT INTO asset_telemetry_logs (
        asset_id,
        recorded_by,
        event_type,
        payload,
        client_timestamp
    ) VALUES (
        p_asset_id,
        p_recorded_by,
        p_event_type,
        p_payload,
        p_client_timestamp
    );

    RETURN 'SUCCESS';

EXCEPTION 
    -- Interceptar errores de integridad referencial, violaciones de checks o tipos malformados
    WHEN foreign_key_violation OR numeric_value_out_of_range OR check_violation OR data_exception THEN
        INSERT INTO telemetry_dead_letter_logs (
            asset_id,
            recorded_by,
            event_type,
            payload,
            client_timestamp,
            error_code,
            error_message
        ) VALUES (
            p_asset_id,
            p_recorded_by,
            p_event_type,
            p_payload,
            p_client_timestamp,
            SQLSTATE,
            SQLERRM
        );
        RETURN 'DEAD_LETTER_ROUTED';
    WHEN OTHERS THEN
        -- Errores inesperados de infraestructura crítica se relanzan para abortar
        RAISE;
END;
$$;
