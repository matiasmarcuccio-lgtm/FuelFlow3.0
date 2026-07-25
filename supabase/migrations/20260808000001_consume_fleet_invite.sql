-- 1. Actualizar la tabla fleet_invites existente para adaptarse al nuevo modelo forense
ALTER TABLE public.fleet_invites RENAME COLUMN invite_token TO token;
ALTER TABLE public.fleet_invites DROP COLUMN IF EXISTS is_consumed;
ALTER TABLE public.fleet_invites ADD COLUMN IF NOT EXISTS role VARCHAR(50) DEFAULT 'driver' CHECK (role IN ('driver', 'fitter', 'supervisor'));
ALTER TABLE public.fleet_invites ADD COLUMN IF NOT EXISTS consumed_at TIMESTAMPTZ DEFAULT NULL;
ALTER TABLE public.fleet_invites ADD COLUMN IF NOT EXISTS consumed_by_uid UUID REFERENCES auth.users(id) DEFAULT NULL;

-- 2. Índice parcial para búsquedas ultrarrápidas de tokens vivos y bloqueo de concurrencia
CREATE INDEX IF NOT EXISTS idx_fleet_invites_token ON public.fleet_invites(token) WHERE consumed_at IS NULL;

-- 3. Actualizar fn_generate_fleet_invite para que use 'token' en vez de 'invite_token' y registre el 'role'
CREATE OR REPLACE FUNCTION public.fn_generate_fleet_invite(p_fleet_id UUID)
RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_token VARCHAR(10);
BEGIN
    -- Verificar si el usuario que llama tiene rol FLEET_MANAGER
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role IN ('fleet_manager', 'super_admin')
    ) THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE';
    END IF;

    -- Generar token simple (6 caracteres alfanuméricos en mayúsculas)
    v_token := UPPER(SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 6));

    INSERT INTO public.fleet_invites (fleet_id, token, created_by, role)
    VALUES (p_fleet_id, v_token, auth.uid(), 'driver');

    RETURN v_token;
END;
$$;

-- DROP FUNCTION existente por cambio de tipo de retorno (de BOOLEAN a JSONB)
DROP FUNCTION IF EXISTS public.fn_consume_fleet_invite(VARCHAR);
DROP FUNCTION IF EXISTS public.fn_consume_fleet_invite(VARCHAR(10));

-- 4. El Procedimiento Almacenado Zero-Trust (Guillotina de Token) provisto por el usuario
CREATE OR REPLACE FUNCTION public.fn_consume_fleet_invite(
    p_token VARCHAR(10)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth -- Aislamiento de esquema para prevenir inyecciones
AS $$
DECLARE
    v_invite RECORD;
    v_caller_uid UUID;
BEGIN
    v_caller_uid := auth.uid();
    
    -- ADUANA 0: Verificar identidad básica en el motor
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: La terminal carece de un JWT de dispositivo válido para reclamar una identidad.'
            USING ERRCODE = '40100';
    END IF;

    -- ADUANA 1: Bloqueo transaccional FOR UPDATE contra Double-Spending
    SELECT id, fleet_id, role, expires_at, consumed_at
    INTO v_invite
    FROM public.fleet_invites
    WHERE token = UPPER(TRIM(p_token))
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TOKEN_NOT_FOUND: El código % no existe en los registros del Command Center.', p_token
            USING ERRCODE = 'P0002';
    END IF;

    IF v_invite.consumed_at IS NOT NULL THEN
        RAISE EXCEPTION 'TOKEN_ALREADY_CONSUMED: Este código de enrolamiento ya fue utilizado para vincular otra maquinaria.'
            USING ERRCODE = '40900';
    END IF;

    IF v_invite.expires_at < now() THEN
        RAISE EXCEPTION 'TOKEN_EXPIRED: El código venció el %. Solicite la emisión de un nuevo token por SMS al Fleet Manager.', v_invite.expires_at
            USING ERRCODE = '41000';
    END IF;

    -- TRANSACCIÓN ATÓMICA A: Quemar el token permanentemente
    UPDATE public.fleet_invites
    SET consumed_at = now(),
        consumed_by_uid = v_caller_uid
    WHERE id = v_invite.id;

    -- TRANSACCIÓN ATÓMICA B: Vincular la jurisdicción y el rol en la tabla pública de perfiles
    UPDATE public.profiles
    SET fleet_id = v_invite.fleet_id,
        role = LOWER(v_invite.role),
        updated_at = now()
    WHERE id = v_caller_uid;

    -- Fallback Defensivo: Si por ser un usuario anónimo de GoTrue la fila en profiles no existía aún, se crea in situ
    IF NOT FOUND THEN
        INSERT INTO public.profiles (id, full_name, role, fleet_id, created_at, updated_at)
        VALUES (
            v_caller_uid, 
            'terminal_' || substr(v_caller_uid::text, 1, 8) || '@jitsite.device', 
            LOWER(v_invite.role), 
            v_invite.fleet_id, 
            now(), 
            now()
        );
    END IF;

    -- TRANSACCIÓN ATÓMICA C: Registro inmutable en el libro mayor de auditoría
    INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
    VALUES (
        NULL,
        'TERMINAL OPERATIVA VINCULADA VÍA TOKEN [' || UPPER(TRIM(p_token)) || '] A FLOTA ID: ' || v_invite.fleet_id || ' CON ROL: ' || UPPER(v_invite.role),
        v_caller_uid,
        'closed'
    );

    -- Retorno de carga útil limpia para hidratar la interfaz de la tablet sin recargar
    RETURN jsonb_build_object(
        'success', true,
        'fleet_id', v_invite.fleet_id,
        'assigned_role', LOWER(v_invite.role),
        'operator_uid', v_caller_uid,
        'timestamp', now()
    );
END;
$$;

NOTIFY pgrst, 'reload schema';
