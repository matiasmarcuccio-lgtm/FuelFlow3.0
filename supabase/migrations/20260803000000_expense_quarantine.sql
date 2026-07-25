-- 1. Modificar Outbox para soportar gastos independientes sin certificado
ALTER TABLE public.erp_outbox ALTER COLUMN certificate_id DROP NOT NULL;

-- 2. La Celda de Contención Financiera
CREATE TABLE public.expense_quarantine (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shift_id UUID REFERENCES public.asset_assignments(id) NOT NULL,
    driver_uid UUID REFERENCES auth.users(id) NOT NULL,
    raw_image_url TEXT NOT NULL,
    ocr_confidence NUMERIC CHECK (ocr_confidence BETWEEN 0 AND 100),
    extracted_amount NUMERIC,
    extracted_vendor TEXT,
    expense_category VARCHAR(50) CHECK (expense_category IN ('fuel', 'toll', 'maintenance_parts', 'other')),
    status VARCHAR(20) DEFAULT 'pending_review' CHECK (status IN ('pending_review', 'approved', 'rejected')),
    reviewed_by_uid UUID REFERENCES auth.users(id),
    review_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Fricción Forense: La IA propone, el humano dispone
CREATE OR REPLACE FUNCTION public.process_quarantined_expense(
    p_expense_id UUID, 
    p_status VARCHAR, 
    p_corrected_amount NUMERIC, 
    p_notes TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_actor_role TEXT;
    v_expense RECORD;
BEGIN
    v_actor_role := current_setting('request.jwt.claims', true)::jsonb ->> 'user_role';

    -- Escudo Jurisdiccional
    IF v_actor_role NOT IN ('supervisor', 'fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'WHS_UNAUTHORIZED: Solo los supervisores tácticos pueden auditar gastos análogos.';
    END IF;

    -- Extraer el gasto
    SELECT * INTO v_expense FROM public.expense_quarantine WHERE id = p_expense_id FOR UPDATE;

    IF NOT FOUND OR v_expense.status != 'pending_review' THEN
        RAISE EXCEPTION 'STATE_VIOLATION: El gasto ya fue procesado o no existe en la cuarentena.';
    END IF;

    -- Actualizar estado
    UPDATE public.expense_quarantine
    SET status = p_status,
        reviewed_by_uid = auth.uid(),
        review_notes = p_notes,
        updated_at = now()
    WHERE id = p_expense_id;

    -- Inyección directa al Outbox como un evento separado
    IF p_status = 'approved' THEN
        INSERT INTO public.erp_outbox (id, certificate_id, payload)
        VALUES (
            gen_random_uuid(),
            NULL,
            jsonb_build_object(
                'event', 'billing.expense.approved',
                'expense_id', p_expense_id,
                'shift_id', v_expense.shift_id,
                'category', v_expense.expense_category,
                'approved_amount', p_corrected_amount,
                'auditor_uid', auth.uid(),
                'timestamp', now()
            )
        );
    END IF;
END;
$$;
