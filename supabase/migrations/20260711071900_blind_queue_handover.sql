-- 1. Erradicar el endpoint que exponía los hashes criptográficos offline
DROP FUNCTION IF EXISTS get_project_crew_hashes(uuid);

-- 2. Trigger para procesar de forma asíncrona y blindada el handover_signature (Blind Queue)
CREATE OR REPLACE FUNCTION process_handover_signature()
RETURNS TRIGGER AS $$
DECLARE
    v_pin TEXT;
    v_operator_id UUID;
    v_pin_hash TEXT;
    v_is_valid BOOLEAN;
BEGIN
    -- Solo interceptar eventos handover_signature
    IF NEW.event_type = 'handover_signature' THEN
        -- Extraer el PIN plano que viene en la telemetría (Blind Queue)
        v_pin := NEW.payload->>'pin';
        v_operator_id := NEW.recorded_by;
        
        -- Si no trae pin, es una aserción fraudulenta instantánea
        IF v_pin IS NULL THEN
            UPDATE assets SET status = 'out_of_service' WHERE id = NEW.asset_id;
            PERFORM net.http_post(
                url:='https://n8n.fuelflow.com/webhook/handover-fraud',
                body:=json_build_object('asset_id', NEW.asset_id, 'operator_id', v_operator_id, 'reason', 'missing_pin')::jsonb
            );
            NEW.payload := NEW.payload - 'pin';
            RETURN NEW;
        END IF;

        -- Buscar el hash real del operador en la base de datos central
        SELECT pin_hash INTO v_pin_hash
        FROM profiles
        WHERE id = v_operator_id;
        
        -- Validar matemáticamente usando pgcrypto
        v_is_valid := (v_pin_hash = crypt(v_pin, v_pin_hash));

        -- Si la firma criptográfica es falsa, disparar RED TAG y alerta forense
        IF NOT v_is_valid THEN
            -- Inyectar Red Tag al activo
            UPDATE assets SET status = 'out_of_service' WHERE id = NEW.asset_id;
            
            -- Disparar webhook a n8n para alertar a la gerencia
            PERFORM net.http_post(
                url:='https://n8n.fuelflow.com/webhook/handover-fraud',
                body:=json_build_object('asset_id', NEW.asset_id, 'operator_id', v_operator_id, 'reason', 'invalid_pin')::jsonb
            );
        END IF;
        
        -- Amnesia de base de datos: Borrar el PIN plano del JSON antes de guardarlo en disco (Data at Rest)
        NEW.payload := NEW.payload - 'pin';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Crear el Trigger sobre asset_telemetry_logs (BEFORE INSERT para mutar el payload)
DROP TRIGGER IF EXISTS trg_intercept_handover ON asset_telemetry_logs;
CREATE TRIGGER trg_intercept_handover
BEFORE INSERT ON asset_telemetry_logs
FOR EACH ROW
EXECUTE FUNCTION process_handover_signature();
