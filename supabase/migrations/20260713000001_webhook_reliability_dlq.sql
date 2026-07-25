-- 20260713000001_webhook_reliability_dlq.sql
-- Migración para Tolerancia a Fallos en Orquestación (DLQ, Exponential Backoff, Idempotencia)

SET search_path = public, postgis, net;

-- 1. Evolución del esquema de la tabla de eventos para retención del puntero
ALTER TABLE webhook_events
ADD COLUMN IF NOT EXISTS request_id BIGINT,
ADD COLUMN IF NOT EXISTS retry_count INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS next_retry_at TIMESTAMPTZ DEFAULT now(),
ADD COLUMN IF NOT EXISTS error_message TEXT;

-- 2. Creación de la Tabla Estricta de Cola Muerta (Dead Letter Queue)
CREATE TABLE IF NOT EXISTS dead_letter_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_event_id UUID NOT NULL,
    event_type TEXT NOT NULL,
    payload JSONB NOT NULL,
    last_error TEXT,
    failed_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Refactorización del Trigger Asíncrono (Captura de puntero, Timeouts y Riqueza de Payload)
CREATE OR REPLACE FUNCTION push_to_n8n_webhook()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    -- URL de n8n orquestador
    v_n8n_webhook_url TEXT := 'https://n8n.fuelflow.example.com/webhook/fuelflow-events';
    v_request_body JSONB;
    v_request_id BIGINT;
BEGIN
    -- Riqueza del Payload: Firma Forense completa inyectada
    v_request_body := jsonb_build_object(
        'event_id', NEW.id,
        'event_type', NEW.event_type,
        'payload', NEW.payload,
        'created_at', NEW.created_at
    );

    -- Captura del Puntero y Timeouts Estrictos (5 segundos máximo)
    -- Inyección del encabezado x-idempotency-key para garantizar la unicidad del flujo
    SELECT net.http_post(
        url := v_n8n_webhook_url,
        body := v_request_body,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-idempotency-key', NEW.id::text
        ),
        timeout_milliseconds := 5000
    ) INTO v_request_id;

    -- Almacenar el request_id retornado y mutar el estado
    NEW.request_id := v_request_id;
    NEW.status := 'dispatched_to_pgnet';
    NEW.retry_count := 0;
    
    RETURN NEW;
END;
$$;

-- 4. Función de Barrido Asíncrono (Retries Prolongados y DLQ)
CREATE OR REPLACE FUNCTION process_webhook_responses()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    r RECORD;
    v_new_request_id BIGINT;
    v_backoff_minutes INT;
BEGIN
    -- Barrer eventos despachados cuyo tiempo de reintento haya expirado (Batch Limit 50)
    FOR r IN 
        SELECT we.*, nr.status_code, nr.error_msg, nr.id as response_id
        FROM webhook_events we
        LEFT JOIN net.http_response nr ON we.request_id = nr.id
        WHERE we.status = 'dispatched_to_pgnet'
          AND (we.next_retry_at IS NULL OR we.next_retry_at <= now())
        ORDER BY we.created_at ASC
        LIMIT 50
    LOOP
        -- Si aún no hay respuesta de pg_net, continuar (está en vuelo)
        IF r.response_id IS NULL AND r.request_id IS NOT NULL THEN
            CONTINUE;
        END IF;

        -- Evaluar éxito
        IF r.status_code >= 200 AND r.status_code < 300 THEN
            UPDATE webhook_events 
            SET status = 'delivered', error_message = NULL 
            WHERE id = r.id;
        ELSE
            -- Fallo o Timeout de Red
            -- max_retries innegociable establecido en 5
            IF r.retry_count >= 5 THEN
                -- Arrojar a la Cola de la Muerte (DLQ)
                INSERT INTO dead_letter_queue (original_event_id, event_type, payload, last_error)
                VALUES (r.id, r.event_type, r.payload, COALESCE(r.error_msg, 'HTTP ' || r.status_code::text));
                
                UPDATE webhook_events 
                SET status = 'failed', error_message = COALESCE(r.error_msg, 'Exhausted retries. HTTP ' || r.status_code::text)
                WHERE id = r.id;
            ELSE
                -- Retroceso Progresivo Prolongado (1m, 5m, 15m, 30m, 60m)
                v_backoff_minutes := CASE 
                    WHEN r.retry_count = 0 THEN 1
                    WHEN r.retry_count = 1 THEN 5
                    WHEN r.retry_count = 2 THEN 15
                    WHEN r.retry_count = 3 THEN 30
                    WHEN r.retry_count = 4 THEN 60
                    ELSE 60
                END;

                -- Reinyectar el webhook
                SELECT net.http_post(
                    url := 'https://n8n.fuelflow.example.com/webhook/fuelflow-events',
                    body := jsonb_build_object(
                        'event_id', r.id,
                        'event_type', r.event_type,
                        'payload', r.payload,
                        'created_at', r.created_at
                    ),
                    headers := jsonb_build_object(
                        'Content-Type', 'application/json',
                        'x-idempotency-key', r.id::text
                    ),
                    timeout_milliseconds := 5000
                ) INTO v_new_request_id;

                UPDATE webhook_events 
                SET retry_count = r.retry_count + 1,
                    next_retry_at = now() + (v_backoff_minutes || ' minutes')::interval,
                    request_id = v_new_request_id,
                    error_message = COALESCE(r.error_msg, 'HTTP ' || r.status_code::text)
                WHERE id = r.id;
            END IF;
        END IF;
    END LOOP;
    
    -- Recolección de Basura Selectiva y Límite de Retención (30 días)
    -- 1. Purgar las peticiones HTTP que el orquestador confirmó exitosamente (delivered)
    DELETE FROM net.http_request 
    WHERE id IN (
        SELECT request_id FROM webhook_events WHERE status = 'delivered'
    );
    
    -- 2. Purgar absolutamente cualquier registro forense mayor a 30 días para evitar asfixia del disco
    DELETE FROM net.http_request WHERE created < (now() - interval '30 days');
    DELETE FROM dead_letter_queue WHERE failed_at < (now() - interval '30 days');
END;
$$;

-- 5. Opcional: Configurar pg_cron para que ejecute el barrido asíncrono
-- Se asume que pg_cron está habilitado. Descomentar si se ejecuta dentro del esquema final
-- SELECT cron.schedule('process_webhook_responses_job', '* * * * *', 'SELECT process_webhook_responses();');
