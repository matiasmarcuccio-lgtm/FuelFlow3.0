-- Migración: Lógica de Gestión de Flotas y Bloqueos Forenses
-- Objetivo: Establecer los cimientos transaccionales para enrolamiento, delegación temporal y despidos seguros.

-- 1. Ampliación de la tabla Profiles
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'ACTIVE';

-- 2. Sistema de Enrolamiento Efímero (Onboarding)
CREATE TABLE IF NOT EXISTS public.fleet_invites (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    fleet_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    invite_token VARCHAR(10) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
    is_consumed BOOLEAN NOT NULL DEFAULT false,
    created_by UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Habilitar RLS para las invitaciones
ALTER TABLE public.fleet_invites ENABLE ROW LEVEL SECURITY;

-- Políticas de invitaciones
CREATE POLICY "Fleet Managers pueden crear invitaciones" ON public.fleet_invites
FOR INSERT WITH CHECK (
    auth.uid() = created_by AND 
    fleet_id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid())
);

CREATE POLICY "Fleet Managers pueden ver sus invitaciones" ON public.fleet_invites
FOR SELECT USING (
    fleet_id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid())
);

-- RPC 1: Generar invitación (Fleet Manager)
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
        WHERE id = auth.uid() AND role IN ('FLEET_MANAGER', 'SUPER_ADMIN')
    ) THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE';
    END IF;

    -- Generar token simple (6 caracteres alfanuméricos en mayúsculas)
    v_token := UPPER(SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 6));

    INSERT INTO public.fleet_invites (fleet_id, invite_token, created_by)
    VALUES (p_fleet_id, v_token, auth.uid());

    RETURN v_token;
END;
$$;

-- RPC 2: Consumir invitación (Driver Onboarding)
CREATE OR REPLACE FUNCTION public.fn_consume_fleet_invite(p_token VARCHAR)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_invite RECORD;
BEGIN
    -- Buscar la invitación válida
    SELECT * INTO v_invite 
    FROM public.fleet_invites 
    WHERE invite_token = p_token AND is_consumed = false FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'INVITE_NOT_FOUND';
    END IF;

    IF v_invite.expires_at < NOW() THEN
        RAISE EXCEPTION 'INVITE_EXPIRED';
    END IF;

    -- Actualizar el perfil del usuario actual
    UPDATE public.profiles
    SET 
        fleet_id = v_invite.fleet_id,
        role = 'DRIVER',
        status = 'ACTIVE'
    WHERE id = auth.uid();

    -- Marcar invitación como consumida
    UPDATE public.fleet_invites
    SET is_consumed = true
    WHERE id = v_invite.id;

    RETURN true;
END;
$$;

-- 3. Kill Switch y Bloqueo Forense (Despido de Conductor)
CREATE OR REPLACE FUNCTION public.fn_revoke_driver_access(p_driver_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_active_loads INT;
BEGIN
    -- Validar permisos del solicitante
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role IN ('FLEET_MANAGER', 'SUPER_ADMIN')
    ) THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE';
    END IF;

    -- Bloqueo Forense: Comprobar si el conductor tiene cargas en tránsito
    SELECT COUNT(id) INTO v_active_loads
    FROM public.load_offers
    WHERE driver_id = p_driver_id 
    AND status IN ('PENDING', 'LOADING', 'IN_TRANSIT', 'AT_WEIGHBRIDGE');

    IF v_active_loads > 0 THEN
        -- El error exacto que la UI debe atrapar
        RAISE EXCEPTION 'ACTIVE_TRANSIT_LOCK';
    END IF;

    -- Ejecutar Baja Definitiva
    UPDATE public.profiles
    SET status = 'INACTIVE'
    WHERE id = p_driver_id;

    RETURN true;
END;
$$;

-- 4. Relevo Táctico Temporal (Shift Override)
CREATE OR REPLACE FUNCTION public.fn_override_shift_assignment(p_absent_driver_id UUID, p_reserve_driver_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_shift RECORD;
BEGIN
    -- Validar permisos del solicitante
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role IN ('FLEET_MANAGER', 'SUPER_ADMIN')
    ) THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE';
    END IF;

    -- Obtener el turno activo del conductor ausente
    SELECT * INTO v_current_shift
    FROM public.shift_assignments
    WHERE driver_id = p_absent_driver_id AND status = 'ACTIVE'
    LIMIT 1 FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NO_ACTIVE_SHIFT';
    END IF;

    -- Graceful Shutdown: Cerrar el turno del conductor ausente
    UPDATE public.shift_assignments
    SET 
        status = 'COMPLETED',
        detach_reason = 'SHIFT_OVERRIDE',
        updated_at = NOW()
    WHERE id = v_current_shift.id;

    -- Iniciar el nuevo turno para el conductor de reserva heredando vehículo y orden maestra
    INSERT INTO public.shift_assignments (
        fleet_id,
        driver_id,
        vehicle_id,
        master_order_id,
        status,
        intent_to_detach
    ) VALUES (
        v_current_shift.fleet_id,
        p_reserve_driver_id,
        v_current_shift.vehicle_id,
        v_current_shift.master_order_id,
        'ACTIVE',
        false
    );

    RETURN true;
END;
$$;
