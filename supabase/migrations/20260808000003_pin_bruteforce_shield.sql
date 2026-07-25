-- Eliminar la versión previa de la función si existiera (debido al cambio de tipo de retorno de BOOLEAN a JSONB)
DROP FUNCTION IF EXISTS public.fn_verify_operator_pin(VARCHAR(4));

-- 1. Inyectar columnas de rastreo forense de ataques en la tabla de perfiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pin_failed_attempts INT DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pin_locked_until TIMESTAMPTZ DEFAULT NULL;

-- 2. ESCUDO FÍSICO: Revocar lectura y escritura pública sobre el contador de fallos
REVOKE ALL (pin_failed_attempts, pin_locked_until) ON public.profiles FROM authenticated, anon;

-- 3. Procedimiento Almacenado de Verificación con Retroceso Geométrico
CREATE OR REPLACE FUNCTION public.fn_verify_operator_pin(
    p_pin VARCHAR(4)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
    v_caller_uid UUID;
    v_profile RECORD;
    v_lockout_duration INTERVAL;
    v_attempts_left INT;
BEGIN
    v_caller_uid := auth.uid();

    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: No hay sesión activa en la terminal.' USING ERRCODE = '40100';
    END IF;

    -- Bloqueo FOR UPDATE para evitar que scripts asíncronos evadan el contador enviando 50 peticiones simultáneas
    SELECT pin_hash, pin_failed_attempts, pin_locked_until, full_name 
    INTO v_profile 
    FROM public.profiles 
    WHERE id = v_caller_uid 
    FOR UPDATE;

    IF NOT FOUND OR v_profile.pin_hash IS NULL THEN
        RAISE EXCEPTION 'PIN_NOT_SET: El operario no ha sellado su PIN militar aún.' USING ERRCODE = '42501';
    END IF;

    -- ADUANA 1: Evaluar si el cronómetro de exclusión sigue activo
    IF v_profile.pin_locked_until IS NOT NULL AND v_profile.pin_locked_until > now() THEN
        RETURN jsonb_build_object(
            'success', false,
            'status', 'LOCKED_OUT',
            'locked_until', v_profile.pin_locked_until,
            'seconds_remaining', EXTRACT(EPOCH FROM (v_profile.pin_locked_until - now()))::INT,
            'msg', 'Terminal temporalmente congelada por múltiples intentos fallidos.'
        );
    END IF;

    -- ADUANA 2: Verificación criptográfica (bcrypt Blowfish)
    IF v_profile.pin_hash = crypt(p_pin, v_profile.pin_hash) THEN
        -- ÉXITO: Limpiamos el historial de fallos y liberamos el acceso
        UPDATE public.profiles 
        SET pin_failed_attempts = 0, 
            pin_locked_until = NULL,
            updated_at = now() 
        WHERE id = v_caller_uid;

        RETURN jsonb_build_object(
            'success', true,
            'status', 'AUTHORIZED',
            'operator_uid', v_caller_uid,
            'timestamp', now()
        );
    END IF;

    -- FALLO CRIPTOGRÁFICO: Incrementamos el contador de infracciones
    v_profile.pin_failed_attempts := v_profile.pin_failed_attempts + 1;
    v_attempts_left := GREATEST(0, 3 - v_profile.pin_failed_attempts);

    -- Cálculo del Retroceso Geométrico:
    -- Intento 3 fallido = 60 segundos (1 min)
    -- Intento 4 fallido = 300 segundos (5 min)
    -- Intento 5+ fallido = 900 segundos (15 min) + Sirena de Ciberseguridad
    IF v_profile.pin_failed_attempts >= 3 THEN
        IF v_profile.pin_failed_attempts = 3 THEN
            v_lockout_duration := interval '1 minute';
        ELSIF v_profile.pin_failed_attempts = 4 THEN
            v_lockout_duration := interval '5 minutes';
        ELSE
            v_lockout_duration := interval '15 minutes';
            
            -- Disparo forense al libro mayor al alcanzar el umbral crítico
            INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
            VALUES (
                NULL, 
                'ALERTA DE SEGURIDAD WHS: FUERZA BRUTA DETECTADA EN TERMINAL PARA UID ' || v_caller_uid || '. BLOQUEO DE 15 MINUTOS APLICADO.', 
                v_caller_uid, 
                'closed'
            );
        END IF;

        UPDATE public.profiles 
        SET pin_failed_attempts = v_profile.pin_failed_attempts,
            pin_locked_until = now() + v_lockout_duration,
            updated_at = now() 
        WHERE id = v_caller_uid;

        RETURN jsonb_build_object(
            'success', false,
            'status', 'LOCKED_OUT',
            'locked_until', now() + v_lockout_duration,
            'seconds_remaining', EXTRACT(EPOCH FROM v_lockout_duration)::INT,
            'msg', 'Umbral de seguridad excedido. Sistema en retroceso geométrico.'
        );
    ELSE
        -- Aún le quedan intentos antes de activar la exclusión
        UPDATE public.profiles 
        SET pin_failed_attempts = v_profile.pin_failed_attempts,
            updated_at = now() 
        WHERE id = v_caller_uid;

        RETURN jsonb_build_object(
            'success', false,
            'status', 'INVALID_PIN',
            'attempts_left', v_attempts_left,
            'msg', 'PIN incorrecto. Le quedan ' || v_attempts_left || ' intentos antes del bloqueo operativo.'
        );
    END IF;
END;
$$;


-- Función de Resurrección Administrativa para el Fleet Manager
CREATE OR REPLACE FUNCTION public.fn_override_pin_lockout(
    p_target_operator_uid UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_actor_role TEXT;
BEGIN
    SELECT LOWER(role) INTO v_actor_role FROM public.profiles WHERE id = auth.uid();

    -- Esclusa Zero-Trust: Solo jerarquía superior puede indultar bloqueos de seguridad
    IF v_actor_role NOT IN ('fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'JURISDICCIÓN DENEGADA: Su sesión carece de autoridad para restablecer terminales bloqueadas.'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.profiles
    SET pin_failed_attempts = 0,
        pin_locked_until = NULL,
        updated_at = now()
    WHERE id = p_target_operator_uid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TARGET_NOT_FOUND: El perfil del operador no existe en el catálogo.' USING ERRCODE = 'P0002';
    END IF;

    -- Registro en libro mayor forense
    INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
    VALUES (
        NULL,
        'INDULTO ADMINISTRATIVO DE PIN APLICADO POR ' || auth.uid() || ' FAVOR DE OPERARIO ' || p_target_operator_uid,
        auth.uid(),
        'closed'
    );

    RETURN jsonb_build_object('success', true, 'unlocked_uid', p_target_operator_uid, 'timestamp', now());
END;
$$;

NOTIFY pgrst, 'reload schema';
