-- 0. Permitir el estado 'suspended' en la tabla de perfiles
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check CHECK (role IN ('super_admin', 'fleet_manager', 'supervisor', 'driver', 'suspended', 'fitter'));

-- 1. Tabla de Auditoría de Elevación y Revocación de Privilegios
CREATE TABLE IF NOT EXISTS public.role_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_user_id UUID REFERENCES auth.users(id) NOT NULL,
    granted_by_user_id UUID REFERENCES auth.users(id) NOT NULL,
    previous_role TEXT NOT NULL,
    new_role TEXT NOT NULL,
    action_type TEXT CHECK (action_type IN ('ELEVATION', 'REVOCATION')),
    justification TEXT NOT NULL,
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Solo los administradores pueden leer el historial de auditoría
ALTER TABLE public.role_audit_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY role_audit_logs_read_policy ON public.role_audit_logs
    FOR SELECT USING (
        (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin'
    );

-- 2. El Motor de Elevación (Ascenso)
CREATE OR REPLACE FUNCTION public.fn_elevate_user_role(
    p_target_id UUID,
    p_new_role TEXT,
    p_justification TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth -- Necesario para garantizar contexto seguro
AS $$
DECLARE
    v_executor_role TEXT;
    v_aal_level TEXT;
    v_previous_role TEXT;
BEGIN
    -- 2.1 Aserción Criptográfica de Hardware (AAL2) extraída directamente del JWT activo
    v_aal_level := current_setting('request.jwt.claims', true)::jsonb ->> 'aal';
    IF v_aal_level IS DISTINCT FROM 'aal2' THEN
        RAISE EXCEPTION 'AAL2 Required: MFA Hardware verification is strictly required for this operation.';
    END IF;

    -- 2.2 Validación Estricta de Identidad Ejecutora (Debe ser super_admin)
    SELECT role INTO v_executor_role FROM public.profiles WHERE id = auth.uid();
    IF v_executor_role IS DISTINCT FROM 'super_admin' THEN
        RAISE EXCEPTION 'Access Denied: Only a Super Admin can elevate roles.';
    END IF;

    -- 2.3 Validación Implacable de Jerarquías Fantasma (ENUM en código duro)
    IF p_new_role NOT IN ('driver', 'supervisor', 'fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'Invalid Role: Attempted to inject a ghost hierarchy. Operation aborted.';
    END IF;

    -- 2.4 Obtener el rol actual para el registro de auditoría
    SELECT role INTO v_previous_role FROM public.profiles WHERE id = p_target_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target user profile not found.';
    END IF;

    -- 2.5 Ejecutar la promoción
    UPDATE public.profiles
    SET role = p_new_role
    WHERE id = p_target_id;

    -- 2.6 Sellar la auditoría
    INSERT INTO public.role_audit_logs (
        target_user_id, granted_by_user_id, previous_role, new_role, action_type, justification
    ) VALUES (
        p_target_id, auth.uid(), v_previous_role, p_new_role, 'ELEVATION', p_justification
    );

    RETURN 'SUCCESS: Role elevated mathematically verified.';
END;
$$;

-- 3. El Motor de Revocación (Degradación y Cuarentena)
CREATE OR REPLACE FUNCTION public.fn_revoke_user_role(
    p_target_id UUID,
    p_new_role TEXT, -- ej. 'driver' o 'suspended' (si se añade a la app)
    p_justification TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth -- CRÍTICO: auth path requerido para destruir la sesión
AS $$
DECLARE
    v_executor_role TEXT;
    v_aal_level TEXT;
    v_previous_role TEXT;
BEGIN
    -- 3.1 Aserción Criptográfica de Hardware (AAL2) extraída directamente del JWT activo
    v_aal_level := current_setting('request.jwt.claims', true)::jsonb ->> 'aal';
    IF v_aal_level IS DISTINCT FROM 'aal2' THEN
        RAISE EXCEPTION 'AAL2 Required: MFA Hardware verification is strictly required for this operation.';
    END IF;

    -- 3.2 Validación Estricta de Identidad Ejecutora (Debe ser super_admin)
    SELECT role INTO v_executor_role FROM public.profiles WHERE id = auth.uid();
    IF v_executor_role IS DISTINCT FROM 'super_admin' THEN
        RAISE EXCEPTION 'Access Denied: Only a Super Admin can revoke roles.';
    END IF;

    -- 3.3 Validación de roles degradados permitidos ('driver' como base segura)
    IF p_new_role NOT IN ('driver', 'suspended') THEN
        RAISE EXCEPTION 'Invalid Role: Revocation target role must be driver or suspended.';
    END IF;

    -- 3.4 Obtener el rol actual
    SELECT role INTO v_previous_role FROM public.profiles WHERE id = p_target_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target user profile not found.';
    END IF;

    -- 3.5 Ejecutar la degradación en la capa operativa
    UPDATE public.profiles
    SET role = p_new_role
    WHERE id = p_target_id;

    -- 3.6 DESTRUCCIÓN FÍSICA DE LA RED (Aniquilar sesiones activas del usuario)
    -- Al borrar el token de la tabla auth.sessions y auth.refresh_tokens, el JWT del objetivo será
    -- invalidado en la próxima validación de la red, expulsándolo de inmediato de su Kiosco/Tablet.
    DELETE FROM auth.sessions WHERE user_id = p_target_id;
    DELETE FROM auth.refresh_tokens WHERE user_id = p_target_id;
    DELETE FROM auth.mfa_amr_claims WHERE session_id IN (SELECT id FROM auth.sessions WHERE user_id = p_target_id);

    -- 3.7 Sellar la auditoría forense
    INSERT INTO public.role_audit_logs (
        target_user_id, granted_by_user_id, previous_role, new_role, action_type, justification
    ) VALUES (
        p_target_id, auth.uid(), v_previous_role, p_new_role, 'REVOCATION', p_justification
    );

    RETURN 'SUCCESS: Role revoked and active sessions physically destroyed.';
END;
$$;
