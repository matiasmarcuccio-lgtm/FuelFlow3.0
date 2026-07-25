-- 1. Inyectar columna de notas de resolución técnica en la tabla de bloqueos (por si no existe)
ALTER TABLE public.asset_lockouts ADD COLUMN IF NOT EXISTS resolution_notes TEXT DEFAULT NULL;

-- 2. EL PROCEDIMIENTO ALMACENADO DE INDULTO INDUSTRIAL (CAPA 0)
CREATE OR REPLACE FUNCTION public.fn_release_asset_lockout(
    p_asset_id UUID,
    p_resolution_notes TEXT,
    p_fitter_pin VARCHAR(4)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
    v_caller_uid UUID;
    v_actor_profile RECORD;
    v_active_lockout RECORD;
    v_asset_fleet_id UUID;
BEGIN
    v_caller_uid := auth.uid();

    -- ADUANA 0: Autenticación activa requerida
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: No hay sesión activa en el terminal del taller.'
            USING ERRCODE = '40100';
    END IF;

    -- ADUANA 1: Verificar identidad, jurisdicción de flota y rol soberano
    SELECT fleet_id, role, pin_hash, full_name
    INTO v_actor_profile 
    FROM public.profiles 
    WHERE id = v_caller_uid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'PROFILE_NOT_FOUND: Su identidad no existe en el catálogo biométrico.'
            USING ERRCODE = 'P0002';
    END IF;

    -- Solo un Fitter (mecánico), un Fleet Manager o un Super Admin pueden retirar una Etiqueta de Peligro
    IF v_actor_profile.role NOT IN ('fitter', 'fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'JURISDICCIÓN DENEGADA: Su rol (%) carece de licencia WHS para liberar maquinaria inhabilitada.', UPPER(v_actor_profile.role)
            USING ERRCODE = '42501';
    END IF;

    -- ADUANA 2: Firma Criptográfica Biometric/PIN (El blindaje anti-tablet abandonada)
    IF v_actor_profile.pin_hash IS NULL THEN
        RAISE EXCEPTION 'PIN_NOT_SET: Debe configurar su PIN militar antes de poder firmar indultos mecánicos.'
            USING ERRCODE = '42501';
    END IF;

    IF v_actor_profile.pin_hash != public.crypt(p_fitter_pin, v_actor_profile.pin_hash) THEN
        RAISE EXCEPTION 'PIN_INVALIDO: Firma criptográfica rechazada. El PIN introducido no coincide con el sello del técnico.'
            USING ERRCODE = '42501';
    END IF;

    -- ADUANA 3: Validar directiva legal de reparación
    IF p_resolution_notes IS NULL OR length(trim(p_resolution_notes)) < 10 THEN
        RAISE EXCEPTION 'NOTE_TOO_SHORT: Normativa minera exige al menos 10 caracteres describiendo la reparación técnica o sustitución de piezas ejecutada.'
            USING ERRCODE = '22023';
    END IF;

    -- ADUANA 4: Bloquear la Etiqueta de Peligro para evitar liberaciones concurrentes (Double-Release)
    SELECT id, fleet_id, lockout_reason, locked_by_operator_uid 
    INTO v_active_lockout 
    FROM public.asset_lockouts 
    WHERE asset_id = p_asset_id AND status = 'ACTIVE' 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'LOCKOUT_NOT_FOUND: La maquinaria % no posee ninguna Etiqueta de Peligro activa en este momento.', p_asset_id
            USING ERRCODE = 'P0002';
    END IF;

    -- Aislamiento de Flota (Un mecánico de la Flota A no puede liberar camiones de la Flota B)
    IF v_actor_profile.role != 'super_admin' AND v_active_lockout.fleet_id != v_actor_profile.fleet_id THEN
        RAISE EXCEPTION 'CROSS_FLEET_VIOLATION: Carece de jurisdicción para operar sobre activos de una flota ajena.'
            USING ERRCODE = '42501';
    END IF;

    -- =========================================================================
    -- SECUENCIA ATÓMICA DE LIBERACIÓN (EL ORDEN FÍSICO ES CRÍTICO)
    -- =========================================================================

    -- PASO A: Cortar el candado en la tabla de bloqueos PRIMERO.
    -- Si intentamos cambiar el estado de la máquina antes de esto, nuestro propio 
    -- disparador anti-sabotaje (trg_enforce_whs_lockout) detectará el candado y abortará todo.
    UPDATE public.asset_lockouts
    SET status = 'RELEASED',
        released_at = now(),
        released_by_fitter_uid = v_caller_uid,
        resolution_notes = UPPER(trim(p_resolution_notes))
    WHERE id = v_active_lockout.id;

    -- PASO B: Con la etiqueta liberada, restauramos la maquinaria al estado operativo
    UPDATE public.assets
    SET status = 'AVAILABLE',
        updated_at = now()
    WHERE id = p_asset_id;

    -- PASO C: Cerrar y sellar las órdenes de trabajo urgentes en el libro mayor de mantenimiento
    UPDATE public.maintenance_logs
    SET status = 'closed',
        issue_description = issue_description || ' | 🔧 RESUELTO POR FITTER [' || UPPER(COALESCE(v_actor_profile.full_name, 'DESCONOCIDO')) || ']: ' || UPPER(trim(p_resolution_notes))
    WHERE asset_id = p_asset_id AND status = 'open';

    -- Retorno limpio de telemetría para la interfaz de Vite
    RETURN jsonb_build_object(
        'success', true,
        'action', 'ASSET_RELEASED_TO_SERVICE',
        'asset_id', p_asset_id,
        'lockout_id', v_active_lockout.id,
        'released_by_uid', v_caller_uid,
        'fitter_name', UPPER(COALESCE(v_actor_profile.full_name, 'DESCONOCIDO')),
        'resolution', UPPER(trim(p_resolution_notes)),
        'timestamp', now()
    );
END;
$$;

-- Notificar a PostgREST
NOTIFY pgrst, 'reload schema';
