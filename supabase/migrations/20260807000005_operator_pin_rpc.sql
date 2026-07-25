-- 1. Asegurarnos de que pgcrypto esté habilitado
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. Función para definir el PIN rápido del operador
CREATE OR REPLACE FUNCTION public.fn_set_operator_pin(p_pin TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Validar que el usuario que llama sea un DRIVER
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role = 'DRIVER'
    ) THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE: Solo un operador (Driver) puede establecer su PIN.';
    END IF;

    -- Validar formato (4 dígitos numéricos)
    IF p_pin !~ '^[0-9]{4}$' THEN
        RAISE EXCEPTION 'INVALID_PIN_FORMAT: El PIN debe contener exactamente 4 dígitos.';
    END IF;

    -- Actualizar el perfil en la Capa 0 con el hash del PIN
    UPDATE public.profiles
    SET 
        hashed_pin = crypt(p_pin, gen_salt('bf')),
        updated_at = NOW()
    WHERE id = auth.uid();

    RETURN true;
END;
$$;

-- Refrescar caché de esquema
NOTIFY pgrst, 'reload schema';
