CREATE OR REPLACE FUNCTION public.resurrect_dead_letter(p_outbox_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_actor_role TEXT;
BEGIN
    v_actor_role := current_setting('request.jwt.claims', true)::jsonb ->> 'user_role';

    -- Fricción Criptográfica: Solo administradores de flota pueden forzar la contabilidad
    IF v_actor_role NOT IN ('fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'WHS_UNAUTHORIZED: Solo el gerente de flota puede resucitar registros financieros muertos.';
    END IF;

    -- Transacción Atómica: Resetear contadores y devolver a la cola
    UPDATE public.erp_outbox
    SET status = 'pending',
        retry_count = 0,
        next_retry_at = now(),
        last_error = '[RESURRECTED BY ' || auth.uid() || '] ' || COALESCE(last_error, '')
    WHERE id = p_outbox_id AND status = 'dead_letter';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_VIOLATION: El registro no existe o no está en estado dead_letter.';
    END IF;
END;
$$;
