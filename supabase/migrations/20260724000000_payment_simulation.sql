-- 1. Crear el libro mayor de pagos inmutables (Audit Ledger)
CREATE TABLE IF NOT EXISTS public.billing_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fleet_id UUID REFERENCES public.fleets(id) NOT NULL,
    amount_aud NUMERIC(10, 2) NOT NULL,
    payment_method VARCHAR(50) DEFAULT 'simulated_card_4242',
    stripe_charge_id VARCHAR(100) NOT NULL UNIQUE,
    status VARCHAR(20) DEFAULT 'succeeded' CHECK (status IN ('succeeded', 'failed', 'refunded')),
    executed_by_uid UUID REFERENCES auth.users(id) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Habilitar RLS en el Ledger (por seguridad)
ALTER TABLE public.billing_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "SuperAdmins and Fleet Managers can view billing ledger"
    ON public.billing_ledger FOR SELECT
    USING (
        auth.uid() IN (
            SELECT id FROM public.profiles 
            WHERE role IN ('super_admin', 'fleet_manager')
        )
    );

-- 2. Procedimiento de Liberación Táctica (Estrictamente en minúsculas)
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
    -- Determinar rol desde JWT o consultar profiles directamente para mayor robustez
    SELECT LOWER(role) INTO v_actor_role FROM public.profiles WHERE id = auth.uid();

    -- Escudo Zero-Trust: Solo el administrador de flota o el super_admin pueden pagar la deuda
    IF v_actor_role NOT IN ('fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE: Solo el Fleet Manager autorizado puede liquidar deudas operativas.';
    END IF;

    -- Generar un ID forense simulando el formato estándar de Stripe
    v_receipt_id := 'ch_sim_' || encode(gen_random_bytes(12), 'hex');

    -- Transacción Atómica 1: Registrar el ingreso en el libro mayor
    INSERT INTO public.billing_ledger (fleet_id, amount_aud, stripe_charge_id, executed_by_uid)
    VALUES (p_fleet_id, p_amount_due, v_receipt_id, auth.uid());

    -- Transacción Atómica 2: Descongelar la flota con el string en MINÚSCULAS para evitar el Bug #4/#5
    UPDATE public.fleets
    SET subscription_status = 'active',
        updated_at = now()
    WHERE id = p_fleet_id AND LOWER(subscription_status) IN ('past_due', 'canceled', 'frozen');

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
