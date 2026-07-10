-- 20260713000000_setup_pg_net_webhooks.sql
-- Migración para el Sumidero de Automatización (n8n) utilizando pg_net

SET search_path = public, postgis;

-- 1. Habilitar la extensión pg_net
CREATE EXTENSION IF NOT EXISTS pg_net;

-- 2. Crear la función de Push Asíncrono (Fire and Forget)
CREATE OR REPLACE FUNCTION push_to_n8n_webhook()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    -- La URL base de tu servidor n8n (reemplazar en producción)
    v_n8n_webhook_url TEXT := 'https://n8n.fuelflow.example.com/webhook/fuelflow-events';
    v_request_body JSONB;
BEGIN
    -- Empaquetamos el payload del evento
    v_request_body := jsonb_build_object(
        'event_id', NEW.id,
        'event_type', NEW.event_type,
        'payload', NEW.payload,
        'created_at', NEW.created_at
    );

    -- net.http_post es estrictamente asíncrono.
    -- La transacción de la base de datos (por ejemplo, el Cierre de Turno del Kiosk) 
    -- NUNCA se bloqueará esperando a n8n, garantizando latencia cero en la tablet.
    PERFORM net.http_post(
        url := v_n8n_webhook_url,
        body := v_request_body,
        headers := '{"Content-Type": "application/json"}'::jsonb
    );

    -- Actualizamos el estado interno a procesado de manera inmediata
    NEW.status := 'dispatched_to_pgnet';
    
    RETURN NEW;
END;
$$;

-- 3. Inyectar el trigger en la tabla webhook_events
DROP TRIGGER IF EXISTS trg_push_to_n8n_webhook ON webhook_events;

CREATE TRIGGER trg_push_to_n8n_webhook
BEFORE INSERT ON webhook_events
FOR EACH ROW
EXECUTE FUNCTION push_to_n8n_webhook();
