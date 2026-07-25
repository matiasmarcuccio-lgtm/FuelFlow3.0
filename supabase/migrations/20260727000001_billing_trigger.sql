-- Migración: Gatillo Asíncrono de Ejecución Financiera (Fire-and-Forget)

CREATE OR REPLACE FUNCTION public.notify_edge_function_on_certificate()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_edge_function_url TEXT := current_setting('app.settings.webhook_edge_url', true);
    v_payload JSONB;
    v_request_id BIGINT;
BEGIN
    IF v_edge_function_url IS NULL OR v_edge_function_url = '' THEN
        RETURN NEW;
    END IF;

    -- Construir el payload referencial para la Edge Function
    v_payload := jsonb_build_object(
        'event_type', 'billing.certificate.generated',
        'record_id', NEW.id,
        'assignment_id', NEW.assignment_id,
        'total_billable', NEW.total_billable,
        'generated_at', NEW.generated_at
    );

    -- Disparar y olvidar (Fire-and-Forget) mediante pg_net
    SELECT net.http_post(
        url := v_edge_function_url,
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := v_payload
    ) INTO v_request_id;

    RETURN NEW;
END;
$$;

-- Acoplamiento del Gatillo al Libro Mayor de Certificados
DROP TRIGGER IF EXISTS trg_certificate_webhook ON public.execution_certificates;
CREATE TRIGGER trg_certificate_webhook
AFTER INSERT ON public.execution_certificates
FOR EACH ROW
EXECUTE FUNCTION public.notify_edge_function_on_certificate();
