-- Migración: Emisión de Alertas Críticas (Egress de Auditoría)

CREATE OR REPLACE FUNCTION public.notify_edge_function_on_critical_audit()
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

    -- Filtro de Severidad: Solo emitimos alertas hacia fuera si el cambio afecta el dinero
    IF NEW.target_table NOT IN ('billing_contracts') THEN
        RETURN NEW;
    END IF;

    -- Construir el payload referencial
    v_payload := jsonb_build_object(
        'event_type', 'audit.infrastructure.breach',
        'record_id', NEW.id,
        'target_table', NEW.target_table
    );

    -- Disparar y olvidar (Fire-and-Forget)
    SELECT net.http_post(
        url := v_edge_function_url,
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := v_payload
    ) INTO v_request_id;

    RETURN NEW;
END;
$$;

-- Acoplar el gatillo a la bóveda de auditoría
DROP TRIGGER IF EXISTS trg_critical_audit_webhook ON public.system_audit_logs;
CREATE TRIGGER trg_critical_audit_webhook
AFTER INSERT ON public.system_audit_logs
FOR EACH ROW
EXECUTE FUNCTION public.notify_edge_function_on_critical_audit();
