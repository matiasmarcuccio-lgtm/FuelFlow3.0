-- Capa 0: WHS Pre-Start Interlock Engine

CREATE TABLE IF NOT EXISTS public.whs_prestarts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID REFERENCES public.assets(id) NOT NULL,
    operator_id UUID REFERENCES public.profiles(id) NOT NULL,
    checklist_data JSONB NOT NULL,
    defect_notes JSONB,
    passed BOOLEAN NOT NULL,
    client_timestamp TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.whs_prestarts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Operarios pueden insertar sus propios prestarts"
    ON public.whs_prestarts
    FOR INSERT
    TO authenticated
    WITH CHECK (operator_id = auth.uid());

CREATE POLICY "Fleet managers pueden ver todos los prestarts"
    ON public.whs_prestarts
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE id = auth.uid() AND role IN ('fleet_manager', 'super_admin')
        )
    );

CREATE OR REPLACE FUNCTION public.fn_submit_whs_prestart(
    p_asset_id UUID,
    p_checklist_data JSONB,
    p_defect_notes JSONB,
    p_passed BOOLEAN,
    p_client_timestamp TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_operator_id UUID;
    v_result JSONB;
BEGIN
    -- 1. Identidad
    v_operator_id := auth.uid();
    IF v_operator_id IS NULL THEN
        RAISE EXCEPTION 'NO_AUTHORIZATION: Operario no identificado.';
    END IF;

    -- 2. Registro Forense del Prestart
    INSERT INTO public.whs_prestarts (
        asset_id,
        operator_id,
        checklist_data,
        defect_notes,
        passed,
        client_timestamp
    ) VALUES (
        p_asset_id,
        v_operator_id,
        p_checklist_data,
        p_defect_notes,
        p_passed,
        p_client_timestamp
    );

    -- 3. Guillotina de Enclavamiento
    IF NOT p_passed THEN
        -- Intentar cambiar el estado del activo a OUT_OF_SERVICE
        -- Usamos SQL dinámico o cast explícito si es necesario, pero un simple UPDATE suele bastar
        -- asumiendo que el enum lo soporta. Si falla, el bloque fallará y la transacción hace rollback.
        BEGIN
            UPDATE public.assets 
            SET status = 'OUT_OF_SERVICE'
            WHERE id = p_asset_id;
        EXCEPTION WHEN OTHERS THEN
            -- Si el ENUM no soporta OUT_OF_SERVICE, lo ponemos en MAINTENANCE
            UPDATE public.assets 
            SET status = 'MAINTENANCE'
            WHERE id = p_asset_id;
        END;
        
        -- Lanzar un insert en maintenance_logs para auditoría
        INSERT INTO public.maintenance_logs (
            asset_id,
            reported_by,
            issue_description,
            priority,
            status
        ) VALUES (
            p_asset_id,
            v_operator_id,
            'DEFECTO CRÍTICO PRE-START: ' || (p_defect_notes::text),
            'CRITICAL',
            'PENDING'
        );
    END IF;

    v_result := jsonb_build_object(
        'success', true,
        'passed', p_passed,
        'action_taken', CASE WHEN p_passed THEN 'ASSET_CLEARED' ELSE 'ASSET_LOCKED' END
    );

    RETURN v_result;
END;
$$;

-- Notificar a PostgREST
NOTIFY pgrst, 'reload schema';
