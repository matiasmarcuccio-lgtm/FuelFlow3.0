-- ============================================================================
-- CONDUCTO 1: AISLAMIENTO PENDING_ONBOARDING Y PROMOCIÓN ATÓMICA
-- ============================================================================
BEGIN;

-- 1. Actualizar restricción de roles para admitir el limbo de onboarding
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check 
CHECK (role IN ('super_admin', 'fleet_manager', 'fitter', 'driver', 'account_owner', 'pending_onboarding', 'dispatcher', 'supervisor', 'suspended'));

-- 2. Restricción condicional: fleet_id solo puede ser NULL si el rol es pending_onboarding o super_admin
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS chk_profiles_fleet_id_not_null;
ALTER TABLE public.profiles ADD CONSTRAINT chk_profiles_fleet_id_not_null
CHECK (
    (role IN ('pending_onboarding', 'super_admin')) OR (fleet_id IS NOT NULL)
);

-- 3. Modificar el disparador nativo de GoTrue para atrapar nuevos registros sin invitación
CREATE OR REPLACE FUNCTION public.handle_new_user() 
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public, auth
AS $$
DECLARE
    v_role VARCHAR(50);
    v_fleet_id UUID;
    v_fleet_name TEXT;
BEGIN
    -- Extraer metadatos enviados desde el formulario de registro de React
    v_role := COALESCE(NEW.raw_user_meta_data->>'role', 'pending_onboarding');
    v_fleet_name := NEW.raw_user_meta_data->>'fleet_name';

    -- Si intentan registrarse como account_owner sin pasar por Stripe, los degradamos al limbo
    IF v_role = 'account_owner' THEN
        v_role := 'pending_onboarding';
    END IF;

    -- Si existe una invitación formal (empleado), le respetamos su flota y rol asignado
    IF NEW.raw_user_meta_data->>'invited_fleet_id' IS NOT NULL THEN
        v_fleet_id := (NEW.raw_user_meta_data->>'invited_fleet_id')::uuid;
        v_role := COALESCE(NEW.raw_user_meta_data->>'invited_role', 'driver');
    END IF;

    INSERT INTO public.profiles (
        id, email, full_name, role, fleet_id, created_at
    ) VALUES (
        NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'full_name', 'Usuario Minero'),
        v_role, v_fleet_id, NOW()
    );
    RETURN NEW;
END;
$$;

-- 4. MOTOR ATÓMICO DE PROMOCIÓN (Invocado exclusivamente desde el Webhook de Stripe)
CREATE OR REPLACE FUNCTION public.fn_promote_to_account_owner(
    p_user_uid UUID,
    p_fleet_name VARCHAR(100),
    p_stripe_customer_id VARCHAR(100),
    p_stripe_subscription_id VARCHAR(100)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_new_fleet_id UUID;
    v_current_role VARCHAR(50);
BEGIN
    SELECT role INTO v_current_role FROM public.profiles WHERE id = p_user_uid;
    
    IF v_current_role != 'pending_onboarding' THEN
        RAISE EXCEPTION 'ALERTA DE SEGURIDAD: El usuario % no está en limbo de onboarding (Rol actual: %)', p_user_uid, v_current_role
            USING ERRCODE = '42501';
    END IF;

    -- A. Crear la flota minera con estado comercial activo
    INSERT INTO public.fleets (
        name, stripe_customer_id, stripe_subscription_id, subscription_status, created_at
    ) VALUES (
        p_fleet_name, p_stripe_customer_id, p_stripe_subscription_id, 'ACTIVE', NOW()
    ) RETURNING id INTO v_new_fleet_id;

    -- B. Crear automáticamente la Obra Principal por defecto en la cantera
    INSERT INTO public.project_sites (
        fleet_id, name, status, vault_status, created_at
    ) VALUES (
        v_new_fleet_id, 'Obra Principal Hobart (Heredada)', 'ACTIVE', 'OPERATIONAL', NOW()
    );

    -- C. Ascender al usuario a account_owner y vincularlo a su nueva flota
    UPDATE public.profiles
    SET role = 'account_owner', fleet_id = v_new_fleet_id
    WHERE id = p_user_uid;

    RETURN jsonb_build_object(
        'success', true,
        'fleet_id', v_new_fleet_id,
        'promoted_uid', p_user_uid,
        'fleet_name', p_fleet_name
    );
END;
$$;

COMMIT;
