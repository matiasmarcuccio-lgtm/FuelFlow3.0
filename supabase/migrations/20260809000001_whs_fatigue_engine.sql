-- 1. TABLA TRANSACCIONAL DE JORNADAS Y FATIGA (WORM: Write Once, Read/Append Many)
CREATE TABLE IF NOT EXISTS public.shift_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    operator_uid UUID NOT NULL REFERENCES auth.users(id),
    fleet_id UUID NOT NULL,
    asset_id UUID REFERENCES public.assets(id),
    status VARCHAR(30) NOT NULL CHECK (status IN ('ACTIVE', 'ON_BREAK', 'COMPLETED', 'FATIGUE_LOCKOUT')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_state_change_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    accumulated_work_seconds INT NOT NULL DEFAULT 0,
    accumulated_break_seconds INT NOT NULL DEFAULT 0,
    continuous_work_seconds INT NOT NULL DEFAULT 0,
    ended_at TIMESTAMPTZ DEFAULT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Índice parcial para ubicar el turno activo del operario en microsegundos
CREATE UNIQUE INDEX IF NOT EXISTS idx_active_operator_shift 
ON public.shift_logs(operator_uid) 
WHERE status IN ('ACTIVE', 'ON_BREAK', 'FATIGUE_LOCKOUT');

-- Escudo WORM: Nadie puede borrar ni alterar el historial de turnos pasados
REVOKE DELETE ON public.shift_logs FROM authenticated, anon;

-- 2. EL PROCEDIMIENTO ATÓMICO DE GESTIÓN BIOLÓGICA (CAPA 0)
CREATE OR REPLACE FUNCTION public.fn_execute_shift_action(
    p_action VARCHAR(20), -- 'START_SHIFT', 'START_BREAK', 'END_BREAK', 'END_SHIFT', 'CHECK_STATUS'
    p_asset_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_uid UUID;
    v_profile RECORD;
    v_shift RECORD;
    v_now TIMESTAMPTZ := now();
    v_elapsed_since_change INT;
    v_new_work_sec INT;
    v_new_break_sec INT;
    v_new_continuous_sec INT;
    
    -- Límites legales WorkSafe Tasmania (en segundos)
    c_max_continuous_work INT := 18000; -- 5 horas continuas
    c_max_total_work INT := 43200;      -- 12 horas totales por jornada
    c_min_legal_break INT := 1800;      -- 30 minutos de descanso obligatorio
BEGIN
    v_caller_uid := auth.uid();

    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Terminal carece de sesión AAL2 válida.' USING ERRCODE = '40100';
    END IF;

    SELECT fleet_id, role INTO v_profile FROM public.profiles WHERE id = v_caller_uid;
    IF NOT FOUND OR v_profile.fleet_id IS NULL THEN
        RAISE EXCEPTION 'JURISDICTION_MISSING: Operario no vinculado a una flota minera.' USING ERRCODE = '42501';
    END IF;

    -- Bloqueo pesimista sobre el turno actual del conductor
    SELECT * INTO v_shift FROM public.shift_logs 
    WHERE operator_uid = v_caller_uid AND status IN ('ACTIVE', 'ON_BREAK', 'FATIGUE_LOCKOUT')
    FOR UPDATE;

    -- =========================================================================
    -- ACCIÓN 1: INICIAR JORNADA LABORAL
    -- =========================================================================
    IF p_action = 'START_SHIFT' THEN
        IF FOUND THEN
            RAISE EXCEPTION 'SHIFT_ALREADY_ACTIVE: Ya posee una jornada abierta (ID: %). Finalice el turno actual antes de iniciar uno nuevo.', v_shift.id
                USING ERRCODE = '40900';
        END IF;

        IF p_asset_id IS NULL THEN
            RAISE EXCEPTION 'ASSET_REQUIRED: Debe vincular una maquinaria para abrir el turno.' USING ERRCODE = '22023';
        END IF;

        INSERT INTO public.shift_logs (operator_uid, fleet_id, asset_id, status, started_at, last_state_change_at)
        VALUES (v_caller_uid, v_profile.fleet_id, p_asset_id, 'ACTIVE', v_now, v_now)
        RETURNING * INTO v_shift;

        RETURN jsonb_build_object(
            'success', true, 'status', 'ACTIVE', 'shift_id', v_shift.id,
            'continuous_work_seconds', 0, 'accumulated_work_seconds', 0,
            'seconds_until_break_required', c_max_continuous_work,
            'seconds_until_shift_end', c_max_total_work
        );
    END IF;

    -- Para cualquier otra acción, el turno DEBE existir
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'status', 'NO_ACTIVE_SHIFT', 'msg', 'No hay jornada laboral iniciada.');
    END IF;

    -- Calcular segundos transcurridos desde el último cambio de estado (IGNICIÓN O DESCANSO)
    v_elapsed_since_change := EXTRACT(EPOCH FROM (v_now - v_shift.last_state_change_at))::INT;

    IF v_shift.status = 'ACTIVE' THEN
        v_new_work_sec := v_shift.accumulated_work_seconds + v_elapsed_since_change;
        v_new_continuous_sec := v_shift.continuous_work_seconds + v_elapsed_since_change;
        v_new_break_sec := v_shift.accumulated_break_seconds;
    ELSIF v_shift.status = 'ON_BREAK' THEN
        v_new_work_sec := v_shift.accumulated_work_seconds;
        v_new_continuous_sec := v_shift.continuous_work_seconds;
        v_new_break_sec := v_shift.accumulated_break_seconds + v_elapsed_since_change;
    ELSE
        -- Si está en FATIGUE_LOCKOUT, los contadores se congelan forensementee
        v_new_work_sec := v_shift.accumulated_work_seconds;
        v_new_continuous_sec := v_shift.continuous_work_seconds;
        v_new_break_sec := v_shift.accumulated_break_seconds;
    END IF;

    -- =========================================================================
    -- ADUANA BIOLÓGICA: EVALUACIÓN DE FATIGA Y BLOQUEO AUTOMÁTICO
    -- =========================================================================
    IF (v_new_continuous_sec >= c_max_continuous_work OR v_new_work_sec >= c_max_total_work) AND v_shift.status != 'FATIGUE_LOCKOUT' THEN
        -- GUILLOTINA WHS: El conductor excedió el límite. Bloquear turno y máquina.
        UPDATE public.shift_logs 
        SET status = 'FATIGUE_LOCKOUT',
            accumulated_work_seconds = v_new_work_sec,
            continuous_work_seconds = v_new_continuous_sec,
            last_state_change_at = v_now
        WHERE id = v_shift.id;

        -- Inmovilizar la maquinaria asignada para impedir que siga operando
        IF v_shift.asset_id IS NOT NULL THEN
            UPDATE public.assets SET status = 'OUT_OF_SERVICE', updated_at = v_now WHERE id = v_shift.asset_id;
            
            INSERT INTO public.asset_lockouts (asset_id, fleet_id, locked_by_operator_uid, lockout_reason, status)
            VALUES (v_shift.asset_id, v_profile.fleet_id, v_caller_uid, '🛑 BLOQUEO POR FATIGA WHS: OPERARIO EXCEDIÓ LÍMITE LEGAL DE CONDUCCIÓN CONTINUA', 'ACTIVE');
        END IF;

        INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
        VALUES (v_shift.asset_id, 'ALERTA FATIGA WHS: UID ' || v_caller_uid || ' BLOQUEADO POR EXCEDER HORAS MÁXIMAS.', v_caller_uid, 'open');

        RETURN jsonb_build_object(
            'success', false, 'status', 'FATIGUE_LOCKOUT',
            'msg', 'LÍMITE DE FATIGA EXCEDIDO. MAQUINARIA INHABILITADA BAJO LEY MINERA.',
            'continuous_work_seconds', v_new_continuous_sec, 'accumulated_work_seconds', v_new_work_sec
        );
    END IF;

    -- =========================================================================
    -- ACCIÓN 2: SOLICITAR O RETOMAR DESCANSO / FINALIZAR TURNO / TELEMETRÍA
    -- =========================================================================
    IF p_action = 'START_BREAK' THEN
        IF v_shift.status != 'ACTIVE' THEN
            RAISE EXCEPTION 'INVALID_STATE: Solo puede iniciar descanso estando en un turno activo.' USING ERRCODE = '40000';
        END IF;

        UPDATE public.shift_logs
        SET status = 'ON_BREAK',
            accumulated_work_seconds = v_new_work_sec,
            continuous_work_seconds = v_new_continuous_sec,
            last_state_change_at = v_now
        WHERE id = v_shift.id;

        RETURN jsonb_build_object('success', true, 'status', 'ON_BREAK', 'accumulated_work_seconds', v_new_work_sec);
    
    ELSIF p_action = 'END_BREAK' THEN
        IF v_shift.status != 'ON_BREAK' THEN
            RAISE EXCEPTION 'INVALID_STATE: No se encuentra en descanso actualmente.' USING ERRCODE = '40000';
        END IF;

        -- Evaluar si el descanso cumplió el mínimo legal para reiniciar el reloj continuo (30 min)
        IF v_elapsed_since_change >= c_min_legal_break THEN
            v_new_continuous_sec := 0; -- Reinicio del reloj de 5 horas
        END IF;

        UPDATE public.shift_logs
        SET status = 'ACTIVE',
            accumulated_break_seconds = v_new_break_sec,
            continuous_work_seconds = v_new_continuous_sec,
            last_state_change_at = v_now
        WHERE id = v_shift.id;

        RETURN jsonb_build_object('success', true, 'status', 'ACTIVE', 'continuous_work_seconds', v_new_continuous_sec);
    
    ELSIF p_action = 'END_SHIFT' THEN
        UPDATE public.shift_logs
        SET status = 'COMPLETED',
            accumulated_work_seconds = v_new_work_sec,
            accumulated_break_seconds = v_new_break_sec,
            continuous_work_seconds = v_new_continuous_sec,
            last_state_change_at = v_now,
            ended_at = v_now
        WHERE id = v_shift.id;

        RETURN jsonb_build_object('success', true, 'status', 'COMPLETED', 'total_work_seconds', v_new_work_sec);
    
    ELSIF p_action = 'CHECK_STATUS' THEN
        -- Sincronización pasiva sin mutar estado (Para el polling del HUD en React)
        RETURN jsonb_build_object(
            'success', true,
            'status', v_shift.status,
            'shift_id', v_shift.id,
            'asset_id', v_shift.asset_id,
            'continuous_work_seconds', v_new_continuous_sec,
            'accumulated_work_seconds', v_new_work_sec,
            'accumulated_break_seconds', v_new_break_sec,
            'seconds_until_break_required', GREATEST(0, c_max_continuous_work - v_new_continuous_sec),
            'seconds_until_shift_end', GREATEST(0, c_max_total_work - v_new_work_sec),
            'current_break_duration', CASE WHEN v_shift.status = 'ON_BREAK' THEN v_elapsed_since_change ELSE 0 END,
            'min_legal_break_seconds', c_min_legal_break
        );
    END IF;

    RAISE EXCEPTION 'UNKNOWN_ACTION: La directiva % no es válida en el motor biológico.', p_action USING ERRCODE = '22023';
END;
$$;
