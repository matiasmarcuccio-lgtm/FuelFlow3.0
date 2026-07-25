-- Enable pg_net extension if not enabled
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Function to trigger the webhook
CREATE OR REPLACE FUNCTION trigger_ocr_auditor()
RETURNS TRIGGER AS $$
DECLARE
    payload JSONB;
BEGIN
    payload := jsonb_build_object(
        'type', 'INSERT',
        'table', TG_TABLE_NAME,
        'schema', TG_TABLE_SCHEMA,
        'record', row_to_json(NEW)
    );

    -- Enviar petición asíncrona a la Edge Function
    -- En entorno local, Kong expone las functions en host.docker.internal:54321 o kong:8000
    -- Usaremos la URL pública proporcionada por Supabase local si está disponible
    -- pero para mayor solidez en pg_net usaremos un placeholder reemplazable por variable de entorno 
    -- o directamente la URL local estándar.
    PERFORM net.http_post(
        url := 'http://kong:8000/functions/v1/ocr-auditor',
        body := payload,
        headers := '{"Content-Type": "application/json"}'::jsonb
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach trigger to whs_overrides
DROP TRIGGER IF EXISTS webhook_trigger_ocr_auditor ON public.whs_overrides;
CREATE TRIGGER webhook_trigger_ocr_auditor
AFTER INSERT ON public.whs_overrides
FOR EACH ROW EXECUTE FUNCTION trigger_ocr_auditor();
