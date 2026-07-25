CREATE OR REPLACE FUNCTION public.fn_simulate_payment_success(
    p_fleet_id UUID,
    p_amount_due NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_actor_role TEXT;
    v_receipt_id VARCHAR(100);
BEGIN
    -- Determinar rol
    SELECT LOWER(role::text) INTO v_actor_role FROM public.profiles WHERE id = auth.uid();

    -- Escudo Zero-Trust: Solo el administrador de flota o el super_admin pueden pagar la deuda
    IF v_actor_role NOT IN ('fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE: Solo el Fleet Manager autorizado puede liquidar deudas operativas.';
    END IF;

    -- Generar un ID forense simulando el formato estándar de Stripe
    v_receipt_id := 'ch_sim_' || encode(gen_random_bytes(12), 'hex');

    -- Transacción Atómica 1: Registrar el ingreso en el libro mayor
    INSERT INTO public.billing_ledger (fleet_id, amount_aud, stripe_charge_id, executed_by_uid)
    VALUES (p_fleet_id, p_amount_due, v_receipt_id, auth.uid());

    -- Transacción Atómica 2: Descongelar la flota con el string en MINÚSCULAS
    -- Se corrigió de subscription_status a status según el esquema actual
    UPDATE public.fleets
    SET status = 'active',
        updated_at = now()
    WHERE id = p_fleet_id AND LOWER(status::text) IN ('past_due', 'canceled', 'frozen');

    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_VIOLATION: La flota no existe o no requiere descongelamiento financiero.';
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'fleet_id', p_fleet_id,
        'new_status', 'active',
        'receipt_id', v_receipt_id,
        'timestamp', now()
    );
END;
$$;

-- Refrescar la caché de esquema de PostgREST
NOTIFY pgrst, 'reload schema';
