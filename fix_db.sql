-- 1. Fix the stored procedure to use the correct column name 'status'
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
    SELECT LOWER(role) INTO v_actor_role FROM public.profiles WHERE id = auth.uid();

    IF v_actor_role NOT IN ('fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE: Solo el Fleet Manager autorizado puede liquidar deudas operativas.';
    END IF;

    v_receipt_id := 'ch_sim_' || encode(gen_random_bytes(12), 'hex');

    INSERT INTO public.billing_ledger (fleet_id, amount_aud, stripe_charge_id, executed_by_uid)
    VALUES (p_fleet_id, p_amount_due, v_receipt_id, auth.uid());

    -- Update status instead of subscription_status
    UPDATE public.fleets
    SET status = 'active',
        updated_at = now()
    WHERE id = p_fleet_id AND LOWER(status) IN ('past_due', 'canceled', 'suspended');

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

-- 2. Insert missing profile for the fleet manager since the old trigger failed
INSERT INTO public.profiles (id, role, full_name, fleet_id, status)
VALUES (
    '862622f9-9fc2-48fd-9325-9b7a36f0f52d',
    'fleet_manager',
    'Fleet Manager',
    '48432f69-952e-4536-bd5a-095a3d2bb8cf',
    'ACTIVE'
)
ON CONFLICT (id) DO UPDATE SET 
    role = 'fleet_manager', 
    fleet_id = '48432f69-952e-4536-bd5a-095a3d2bb8cf';

-- 3. Set the fleet status to past_due so the user hits the billing wall naturally
UPDATE public.fleets 
SET status = 'past_due' 
WHERE id = '48432f69-952e-4536-bd5a-095a3d2bb8cf';
