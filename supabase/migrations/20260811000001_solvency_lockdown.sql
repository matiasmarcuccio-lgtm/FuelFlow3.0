-- ============================================================================
-- MIGRACIÓN FORENSE URGENTE: BLINDAJE DE SOLVENCIA RLS Y ANTI-BYPASS
-- ============================================================================
BEGIN;

-- 1. EL JUEZ DE SOLVENCIA FISCAL (INMUNIDAD ABSOLUTA A SECURITY DEFINER)
CREATE OR REPLACE FUNCTION public.fn_enforce_solvency_lockdown()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_status VARCHAR(50);
    v_grace TIMESTAMPTZ;
BEGIN
    -- CIRUGÍA: Usamos la columna "status" que es el nombre real en public.fleets
    SELECT UPPER(status), grace_period_until 
    INTO v_status, v_grace
    FROM public.fleets 
    WHERE id = NEW.fleet_id;

    -- Si no está activa o en prueba, evaluamos la ventana de gracia exactamente
    IF v_status NOT IN ('ACTIVE', 'TRIAL', 'TRIALING') THEN
        IF v_status = 'PAST_DUE' AND v_grace IS NOT NULL AND NOW() <= v_grace THEN
            -- Dentro del amortiguador de 72 horas: permitir operación física
            RETURN NEW;
        ELSE
            RAISE EXCEPTION 'BILLING_LOCKDOWN: Flota suspendida por insolvencia fiscal. El periodo de gracia expiró el % o la membresía fue cancelada.', COALESCE(v_grace::text, 'INMEDIATO')
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- 2. ANCLAJE DE DISPARADORES EN TABLAS TRANSACCIONALES (PROTEGE TODOS LOS RPCs)
DROP TRIGGER IF EXISTS tr_solvency_guard_prestart ON public.whs_prestart_logs;
CREATE TRIGGER tr_solvency_guard_prestart
BEFORE INSERT OR UPDATE ON public.whs_prestart_logs
FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_solvency_lockdown();

DROP TRIGGER IF EXISTS tr_solvency_guard_haul ON public.haul_cycles;
CREATE TRIGGER tr_solvency_guard_haul
BEFORE INSERT OR UPDATE ON public.haul_cycles
FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_solvency_lockdown();

DROP TRIGGER IF EXISTS tr_solvency_guard_lockouts ON public.asset_lockouts;
CREATE TRIGGER tr_solvency_guard_lockouts
BEFORE INSERT OR UPDATE ON public.asset_lockouts
FOR EACH ROW EXECUTE FUNCTION public.fn_enforce_solvency_lockdown();

-- 3. ACTUALIZACIÓN DEL MOTOR DE CAPA 0 PARA RLS Y EVALUACIÓN DE TOKENS
CREATE OR REPLACE FUNCTION public.fn_fleet_can_operate()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_can_operate BOOLEAN;
BEGIN
    -- CIRUGÍA: Usamos la columna "status" que es el nombre real en public.fleets
    SELECT CASE 
        WHEN UPPER(status) IN ('ACTIVE', 'TRIAL', 'TRIALING') THEN true
        WHEN UPPER(status) = 'PAST_DUE' AND grace_period_until IS NOT NULL AND NOW() <= grace_period_until THEN true
        ELSE false
    END INTO v_can_operate
    FROM public.fleets
    WHERE id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid());
    
    RETURN COALESCE(v_can_operate, false);
END;
$$;

-- 4. FORZAR RECARGA DE CACHÉ DE ESQUEMA EN POSTGREST
NOTIFY pgrst, 'reload schema';

COMMIT;
