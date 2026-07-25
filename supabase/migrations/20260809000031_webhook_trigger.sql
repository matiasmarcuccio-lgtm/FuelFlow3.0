-- Migración: Gatillo Asíncrono de Salida (Fire-and-Forget)

-- 1. Habilitar la extensión de red asíncrona
CREATE EXTENSION IF NOT EXISTS pg_net;

-- 2. Función del Gatillo (Emisor de Alta Velocidad)
CREATE OR REPLACE FUNCTION public.notify_edge_function_on_lock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    -- La URL de tu Edge Function se define en los secretos/variables de entorno de PostgreSQL
    v_edge_function_url TEXT := current_setting('app.settings.webhook_edge_url', true);
    v_payload JSONB;
    v_request_id BIGINT;
BEGIN
    -- Mecanismo de seguridad: Si la URL no está configurada, abortar el envío silenciosamente 
    -- para jamás bloquear la transacción WHS del mecánico.
    IF v_edge_function_url IS NULL OR v_edge_function_url = '' THEN
        RETURN NEW;
    END IF;

    -- Construir un payload estrictamente referencial. 
    -- No enviamos todo el log, solo las coordenadas para que Deno haga el trabajo pesado.
    v_payload := jsonb_build_object(
        'event_type', 'asset.locked.critical',
        'record_id', NEW.id,
        'asset_id', NEW.asset_id,
        'locked_at', NEW.locked_at
    );

    -- Disparar y olvidar: net.http_post es asíncrono y no bloquea el COMMIT de la base de datos.
    SELECT net.http_post(
        url := v_edge_function_url,
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := v_payload
    ) INTO v_request_id;

    RETURN NEW;
END;
$$;

-- 3. Acoplamiento del Gatillo a la bóveda forense del taller
DROP TRIGGER IF EXISTS trg_maintenance_lock_webhook ON public.asset_lockouts;
CREATE TRIGGER trg_maintenance_lock_webhook
AFTER INSERT ON public.asset_lockouts
FOR EACH ROW
EXECUTE FUNCTION public.notify_edge_function_on_lock();
