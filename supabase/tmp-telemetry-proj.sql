-- 1. Preparar la tabla de lectura
ALTER TABLE assets
ADD COLUMN IF NOT EXISTS last_known_location JSONB DEFAULT '{"lat": null, "lng": null}'::jsonb;

-- 2. Actualizar el Motor de Proyección (CQRS Trigger)
CREATE OR REPLACE FUNCTION project_asset_telemetry_state()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_asset_timestamp TIMESTAMP WITH TIME ZONE;
BEGIN
    SELECT last_telemetry_timestamp INTO current_asset_timestamp
    FROM assets WHERE id = NEW.asset_id;

    IF NEW.client_timestamp > COALESCE(current_asset_timestamp, '1970-01-01'::timestamptz) THEN
        UPDATE assets
        SET
            status = COALESCE((NEW.payload->>'status'), status),
            last_odometer_checkin = COALESCE((NEW.payload->>'odometer')::NUMERIC, last_odometer_checkin),
            current_project_id = COALESCE((NEW.payload->>'project_id')::UUID, current_project_id),
            -- Nueva línea: Proyectar la ubicación si viene en el payload
            last_known_location = COALESCE((NEW.payload->'location'), last_known_location),
            last_telemetry_timestamp = NEW.client_timestamp
        WHERE id = NEW.asset_id;
    END IF;

    RETURN NEW;
END;
$$;
