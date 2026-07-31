-- Actualización del disparador (Conducto 1) para consumir el token UUIDv4 en tiempo de Onboarding

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_role VARCHAR(50);
    v_fleet_id UUID;
    v_fleet_name TEXT;
    v_invite_token VARCHAR(50); -- Ahora puede recibir el UUIDv4 o el token antiguo
BEGIN
    -- Extraer metadatos enviados desde el formulario de registro de React
    v_role := COALESCE(NEW.raw_user_meta_data->>'role', 'pending_onboarding');
    v_fleet_name := NEW.raw_user_meta_data->>'fleet_name';
    v_invite_token := NEW.raw_user_meta_data->>'invite_token'; -- Extraemos el token embebido en la URL

    -- Si intentan registrarse como account_owner sin pasar por Stripe, los degradamos al limbo
    IF v_role = 'account_owner' THEN
        v_role := 'pending_onboarding';
    END IF;

    -- Si existe una invitación formal (empleado) por Token
    IF v_invite_token IS NOT NULL THEN
        -- Validación estricta y bloqueo for update para prevenir double-spending en el milisegundo cero
        SELECT fleet_id, role 
        INTO v_fleet_id, v_role
        FROM public.fleet_invites
        WHERE token = v_invite_token
          AND consumed_at IS NULL
          AND expires_at > now()
        FOR UPDATE;

        IF FOUND THEN
            -- Quemar (consumir) el token instantáneamente
            UPDATE public.fleet_invites
            SET consumed_at = now(),
                consumed_by_uid = NEW.id
            WHERE token = v_invite_token;
        ELSE
            -- Si el token es inválido, degradar a pending_onboarding
            v_role := 'pending_onboarding';
            v_fleet_id := NULL;
        END IF;
    ELSIF NEW.raw_user_meta_data->>'invited_fleet_id' IS NOT NULL THEN
        -- Fallback por si usan el flujo antiguo sin token
        v_fleet_id := (NEW.raw_user_meta_data->>'invited_fleet_id')::uuid;
        v_role := COALESCE(NEW.raw_user_meta_data->>'invited_role', 'driver');
    END IF;

    -- Inserción final del perfil
    INSERT INTO public.profiles (
        id, full_name, role, fleet_id, created_at
    ) VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
        v_role,
        v_fleet_id,
        now()
    );
    
    RETURN NEW;
END;
$$;
