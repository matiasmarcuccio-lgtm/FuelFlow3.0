-- 1. TABLA INMUTABLE DE BITÁCORAS PRE-START (WORM)
CREATE TABLE IF NOT EXISTS public.whs_prestart_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID NOT NULL REFERENCES public.assets(id),
    operator_uid UUID NOT NULL REFERENCES auth.users(id),
    fleet_id UUID NOT NULL,
    checklist_data JSONB NOT NULL,
    defect_notes JSONB DEFAULT '{}'::jsonb,
    passed BOOLEAN NOT NULL,
    client_timestamp TIMESTAMPTZ NOT NULL,
    server_timestamp TIMESTAMPTZ DEFAULT now()
);

-- Revocar toda modificación o borrado sobre las bitácoras históricas (Nadie puede alterar un pre-start firmado)
REVOKE UPDATE, DELETE ON public.whs_prestart_logs FROM authenticated, anon;

-- 2. TABLA DE ETIQUETAS DE PELIGRO Y ENCLAVAMIENTO FÍSICO (DANGER TAGS)
CREATE TABLE IF NOT EXISTS public.asset_lockouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID NOT NULL,
    fleet_id UUID NOT NULL,
    locked_by_operator_uid UUID NOT NULL REFERENCES auth.users(id),
    prestart_log_id UUID REFERENCES public.whs_prestart_logs(id),
    lockout_reason TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'RELEASED')),
    created_at TIMESTAMPTZ DEFAULT now(),
    released_at TIMESTAMPTZ DEFAULT NULL,
    released_by_fitter_uid UUID DEFAULT NULL
);

CREATE INDEX IF NOT EXISTS idx_active_lockouts ON public.asset_lockouts(asset_id) WHERE status = 'ACTIVE';

-- Asegurar que existan las columnas last_prestart_at y last_prestart_by_uid en assets
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'assets' AND column_name = 'last_prestart_at') THEN
        ALTER TABLE public.assets ADD COLUMN last_prestart_at TIMESTAMPTZ;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'assets' AND column_name = 'last_prestart_by_uid') THEN
        ALTER TABLE public.assets ADD COLUMN last_prestart_by_uid UUID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'assets' AND column_name = 'updated_at') THEN
        ALTER TABLE public.assets ADD COLUMN updated_at TIMESTAMPTZ DEFAULT now();
    END IF;
END $$;

-- 3. EL PROCEDIMIENTO ATÓMICO DE RECEPCIÓN Y ENCLAVAMIENTO
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
SET search_path = public, auth
AS $$
DECLARE
    v_caller_uid UUID;
    v_operator_profile RECORD;
    v_asset_fleet_id UUID;
    v_log_id UUID;
    v_critical_notes TEXT;
BEGIN
    v_caller_uid := auth.uid();

    -- ADUANA 0: Autenticación activa requerida
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Terminal carece de sesión AAL2 válida para firmar bitácoras WHS.'
            USING ERRCODE = '40100';
    END IF;

    -- ADUANA 1: Extraer jurisdicción del operario
    SELECT fleet_id, role, full_name
    INTO v_operator_profile 
    FROM public.profiles 
    WHERE id = v_caller_uid;

    IF v_operator_profile.fleet_id IS NULL THEN
        RAISE EXCEPTION 'JURISDICTION_MISSING: El operario no está asignado a ninguna flota activa.'
            USING ERRCODE = '42501';
    END IF;

    -- ADUANA 2: Verificar que la maquinaria pertenece a la misma flota que el operario (Aislamiento B2B)
    SELECT fleet_id INTO v_asset_fleet_id FROM public.assets WHERE id = p_asset_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ASSET_NOT_FOUND: La maquinaria % no existe en el catálogo.', p_asset_id
            USING ERRCODE = 'P0002';
    END IF;

    IF v_asset_fleet_id != v_operator_profile.fleet_id THEN
        RAISE EXCEPTION 'CROSS_FLEET_VIOLATION: Intento de firmar pre-start en una máquina ajena a su jurisdicción.'
            USING ERRCODE = '42501';
    END IF;

    -- TRANSACCIÓN ATÓMICA A: Inserción inmutable en el libro mayor de bitácoras WHS
    INSERT INTO public.whs_prestart_logs (
        asset_id,
        operator_uid,
        fleet_id,
        checklist_data,
        defect_notes,
        passed,
        client_timestamp
    ) VALUES (
        p_asset_id,
        v_caller_uid,
        v_operator_profile.fleet_id,
        p_checklist_data,
        COALESCE(p_defect_notes, '{}'::jsonb),
        p_passed,
        p_client_timestamp
    ) RETURNING id INTO v_log_id;

    -- BIFURCACIÓN OPERATIVA: ¿La máquina aprobó o falló?
    IF p_passed = TRUE THEN
        -- Si aprobó y estaba disponible, actualizamos su marca de tiempo operativa
        UPDATE public.assets 
        SET last_prestart_at = now(),
            last_prestart_by_uid = v_caller_uid,
            status = 'AVAILABLE',
            updated_at = now()
        WHERE id = p_asset_id AND status != 'OUT_OF_SERVICE';

        RETURN jsonb_build_object(
            'success', true,
            'action', 'PRESTART_APPROVED',
            'log_id', v_log_id,
            'asset_status', 'AVAILABLE',
            'timestamp', now()
        );
    ELSE
        -- GUILLOTINA DE DEFECTO VITAL: La máquina falló ítems críticos
        
        -- Extraer resumen de notas de fallo para la etiqueta de peligro
        SELECT string_agg(key || ': ' || value, ' | ') 
        INTO v_critical_notes
        FROM jsonb_each_text(p_defect_notes);

        -- TRANSACCIÓN ATÓMICA B: Alterar el estado de la máquina a inhabilitada
        UPDATE public.assets 
        SET status = 'OUT_OF_SERVICE',
            updated_at = now()
        WHERE id = p_asset_id;

        -- TRANSACCIÓN ATÓMICA C: Colocar la Etiqueta de Peligro (Danger Tag) en el registro de bloqueos
        INSERT INTO public.asset_lockouts (
            asset_id,
            fleet_id,
            locked_by_operator_uid,
            prestart_log_id,
            lockout_reason,
            status
        ) VALUES (
            p_asset_id,
            v_operator_profile.fleet_id,
            v_caller_uid,
            v_log_id,
            COALESCE(v_critical_notes, 'FALLO CRÍTICO DECLARADO EN PRE-START WHS'),
            'ACTIVE'
        );

        -- TRANSACCIÓN ATÓMICA D: Disparar orden de trabajo urgente para el taller
        INSERT INTO public.maintenance_logs (
            asset_id, 
            issue_description, 
            locked_by_uid, 
            status
        ) VALUES (
            p_asset_id,
            '🛑 ENCLAVAMIENTO WHS POR OPERARIO ' || UPPER(COALESCE(v_operator_profile.full_name, 'DESCONOCIDO')) || '. DEFECTOS: ' || COALESCE(v_critical_notes, 'Ver bitácora ID ' || v_log_id),
            v_caller_uid,
            'open'
        );

        RETURN jsonb_build_object(
            'success', true,
            'action', 'FATAL_DEFECT_LOCKED',
            'log_id', v_log_id,
            'asset_status', 'OUT_OF_SERVICE',
            'lockout_reason', v_critical_notes,
            'timestamp', now()
        );
    END IF;
END;
$$;

-- 4. EL DISPARADOR ANTI-SABOTAJE (trg_enforce_whs_lockout)
CREATE OR REPLACE FUNCTION public.fn_enforce_whs_lockout()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_active_lockout UUID;
BEGIN
    -- Si alguien intenta cambiar el estado de OUT_OF_SERVICE a cualquier otra cosa
    IF OLD.status = 'OUT_OF_SERVICE' AND NEW.status != 'OUT_OF_SERVICE' THEN
        
        -- Verificamos si existe una etiqueta de peligro activa para esta máquina
        SELECT id INTO v_active_lockout 
        FROM public.asset_lockouts 
        WHERE asset_id = OLD.id AND status = 'ACTIVE' 
        LIMIT 1;

        IF FOUND THEN
            RAISE EXCEPTION 'VIOLACIÓN DE ENCLAVAMIENTO WHS: La maquinaria % posee una Etiqueta de Peligro activa (Lockout ID: %). Debe ser liberada por un mecánico certificado (Fitter) mediante el protocolo de indulto antes de cambiar su estado.', OLD.id, v_active_lockout
                USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_whs_lockout ON public.assets;
CREATE TRIGGER trg_enforce_whs_lockout
BEFORE UPDATE ON public.assets
FOR EACH ROW
EXECUTE FUNCTION public.fn_enforce_whs_lockout();

-- Notificar a PostgREST
NOTIFY pgrst, 'reload schema';
