-- Eliminar versiones previas de la función si existieran (para evitar errores por cambio de tipo de retorno)
DROP FUNCTION IF EXISTS public.fn_set_operator_pin(TEXT);
DROP FUNCTION IF EXISTS public.fn_set_operator_pin(VARCHAR);
DROP FUNCTION IF EXISTS public.fn_set_operator_pin(VARCHAR(4));

-- 1. Habilitar la extensión de criptografía nativa de PostgreSQL
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. Inyectar la columna de almacenamiento seguro en perfiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pin_hash TEXT DEFAULT NULL;

-- 3. ESCUDO DE COLUMNA: Nadie puede leer el hash del PIN desde el frontend (ni siquiera el dueño del perfil)
REVOKE SELECT (pin_hash) ON public.profiles FROM authenticated, anon;

-- 4. El Procedimiento Almacenado de Sellado Criptográfico (Capa 0)
CREATE OR REPLACE FUNCTION public.fn_set_operator_pin(
    p_pin VARCHAR(4)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions -- Acceso estricto a pgcrypto y esquemas autorizados
AS $$
DECLARE
    v_caller_uid UUID;
    v_current_fleet UUID;
BEGIN
    v_caller_uid := auth.uid();

    -- ADUANA 0: Autenticación activa requerida
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: No se detectó una sesión AAL2 activa en el terminal.'
            USING ERRCODE = '40100';
    END IF;

    -- ADUANA 1: Validación de sintaxis estricta (Exactamente 4 dígitos numéricos)
    IF p_pin !~ '^[0-9]{4}$' THEN
        RAISE EXCEPTION 'INVALID_PIN_FORMAT: El PIN operativo debe constar estrictamente de 4 dígitos numéricos.'
            USING ERRCODE = '22023';
    END IF;

    -- ADUANA 2: Verificar que el operador ya pertenece a una flota (consumió su token 74BEAF)
    SELECT fleet_id INTO v_current_fleet FROM public.profiles WHERE id = v_caller_uid;
    IF v_current_fleet IS NULL THEN
        RAISE EXCEPTION 'JURISDICTION_MISSING: No puede configurar un PIN sin haber sido vinculado a una flota minera previamente.'
            USING ERRCODE = '42501';
    END IF;

    -- TRANSACCIÓN ATÓMICA A: Generar hash bcrypt con coste 8 y guardar en la columna oculta
    UPDATE public.profiles
    SET pin_hash = crypt(p_pin, gen_salt('bf', 8)),
        updated_at = now()
    WHERE id = v_caller_uid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'PROFILE_NOT_FOUND: El perfil biométrico del operador no existe en la base de datos.'
            USING ERRCODE = 'P0002';
    END IF;

    -- TRANSACCIÓN ATÓMICA B: Asentar el cambio de credenciales en el libro mayor inmutable
    INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
    VALUES (
        NULL,
        'PIN MILITAR OPERATIVO CONFIGURADO Y SELLADO CRIPTOGRÁFICAMENTE PARA UID: ' || v_caller_uid,
        v_caller_uid,
        'closed'
    );

    RETURN jsonb_build_object(
        'success', true,
        'operator_uid', v_caller_uid,
        'fleet_id', v_current_fleet,
        'security_level', 'BCRYPT_SALTED',
        'timestamp', now()
    );
END;
$$;


-- Función complementaria para el inicio de turno diario rápido:
CREATE OR REPLACE FUNCTION public.fn_verify_operator_pin(
    p_pin VARCHAR(4)
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
    v_stored_hash TEXT;
BEGIN
    SELECT pin_hash INTO v_stored_hash FROM public.profiles WHERE id = auth.uid();
    
    IF v_stored_hash IS NULL THEN
        RETURN FALSE; -- El usuario no ha configurado su PIN aún
    END IF;

    -- crypt() evaluado contra el propio hash extrae la sal y verifica si coincide
    RETURN (v_stored_hash = crypt(p_pin, v_stored_hash));
END;
$$;

NOTIFY pgrst, 'reload schema';
