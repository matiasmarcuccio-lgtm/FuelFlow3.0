-- 20260715000000_fitters_override_rpc.sql
-- RPC Transaccional Atómico para el Triaje Mecánico (Fitter's Override)

SET search_path = public, postgis;

-- 1. Crear extensión criptográfica (si no existe) para la validación del PIN
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. Crear tipo ENUM para categorización OLAP de incidentes mecánicos
DO $$ BEGIN
    CREATE TYPE defect_category AS ENUM (
        'hydraulic', 
        'electrical', 
        'engine', 
        'wear_and_tear', 
        'false_alarm'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 3. Inyectar columnas estructuradas en la tabla de defectos
ALTER TABLE plant_defects
ADD COLUMN IF NOT EXISTS category defect_category,
ADD COLUMN IF NOT EXISTS resolution_notes text;

-- 4. Alterar la tabla profiles para incluir el PIN hasheado (2FA Mecánico)
-- Se almacena estrictamente como un hash unidireccional por negligencia cero
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS hashed_pin text;

-- 5. Función RPC Atómica y Segura
CREATE OR REPLACE FUNCTION resolve_plant_defect(
    p_defect_id UUID,
    p_category defect_category,
    p_resolution_notes text,
    p_mechanic_pin text
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER -- Exige ejecución con altos privilegios para evadir RLS temporalmente
AS $$
DECLARE
    v_defect_record RECORD;
    v_mechanic_id UUID;
    v_mechanic_hash TEXT;
    v_asset_id UUID;
BEGIN
    -- Capturar identidad del mecánico
    v_mechanic_id := auth.uid();
    
    IF v_mechanic_id IS NULL THEN
        RAISE EXCEPTION 'Triaje: Se requiere autenticación criptográfica.';
    END IF;

    -- Extraer y validar el PIN del mecánico
    SELECT hashed_pin INTO v_mechanic_hash 
    FROM profiles 
    WHERE id = v_mechanic_id;

    IF v_mechanic_hash IS NULL THEN
        RAISE EXCEPTION 'Triaje: El usuario no tiene un PIN mecánico configurado.';
    END IF;

    -- Validación matemática (pgcrypto)
    IF v_mechanic_hash != crypt(p_mechanic_pin, v_mechanic_hash) THEN
        RAISE EXCEPTION 'Triaje: PIN criptográfico incorrecto. Fitter Override denegado.';
    END IF;

    -- Bloqueo transaccional FOR UPDATE sobre el defecto
    SELECT * INTO v_defect_record 
    FROM plant_defects 
    WHERE id = p_defect_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Triaje: El ticket de defecto % no existe.', p_defect_id;
    END IF;

    IF v_defect_record.status != 'reported' THEN
        RAISE EXCEPTION 'Triaje: El defecto ya no está activo (estado actual: %).', v_defect_record.status;
    END IF;

    v_asset_id := v_defect_record.asset_id;

    -- Ejecutar la Transición Dual Atómica
    
    -- 1. Cerrar el ticket de defecto
    UPDATE plant_defects
    SET 
        status = 'rectified',
        category = p_category,
        resolution_notes = p_resolution_notes,
        rectified_by = v_mechanic_id,
        rectified_at = CURRENT_TIMESTAMP
    WHERE id = p_defect_id;

    -- 2. NOTA: La tabla plant_defects ya tiene un TRIGGER (trg_sync_asset_status_on_defect)
    -- que se dispara AFTER UPDATE OF status y cambia el asset a 'active' o 'out_of_service'.
    -- Por lo tanto, no necesitamos hacer el UPDATE assets manual aquí, el motor transaccional
    -- lo orquesta de manera autónoma. Esto previene dobles responsabilidades en el código.

    -- 3. Emitir el webhook pasivo para notificación externa (n8n)
    INSERT INTO webhook_events (event_type, payload)
    VALUES (
        'plant_defect_rectified',
        jsonb_build_object(
            'defect_id', p_defect_id,
            'asset_id', v_asset_id,
            'mechanic_id', v_mechanic_id,
            'category', p_category,
            'notes', p_resolution_notes,
            'timestamp', CURRENT_TIMESTAMP
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'asset_id', v_asset_id,
        'message', 'Fitter Override exitoso. El hardware ha sido liberado.'
    );
END;
$$;
