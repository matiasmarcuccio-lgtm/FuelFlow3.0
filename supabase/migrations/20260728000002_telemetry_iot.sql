-- Migración: Telemetría de Hardware y Conciliación Telemática

-- 1. Tabla de Lecturas Telemáticas (IoT Telemetry Logs)
CREATE TABLE public.telemetry_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID NOT NULL REFERENCES public.assets(id) ON DELETE CASCADE,
    engine_hours NUMERIC(10, 2) NOT NULL, -- Horómetro real de la ECU/CAN bus
    fuel_level_percent NUMERIC(5, 2),     -- Nivel de combustible %
    coolant_temp_celsius NUMERIC(5, 2),   -- Temperatura de motor
    is_engine_running BOOLEAN NOT NULL DEFAULT false,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexación de alto rendimiento para consultas de series temporales
CREATE INDEX idx_telemetry_asset_time ON public.telemetry_logs (asset_id, recorded_at DESC);

-- Permisos estrictos: La ingesta de IoT solo la realiza el rol de servicio (API Keys/Edge Function)
ALTER TABLE public.telemetry_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow Service Role Ingestion" ON public.telemetry_logs
FOR INSERT WITH CHECK (
    (current_setting('request.jwt.claims', true)::jsonb ->> 'role') = 'service_role'
);

-- 2. Trigger de Protección Mecánica Crítica
CREATE OR REPLACE FUNCTION public.process_telemetry_safety_override()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Si la temperatura supera los 105°C, la máquina entra en modo de alerta crítica
    IF NEW.coolant_temp_celsius >= 105.00 THEN
        -- 1. Inyectar un registro de mantenimiento automático por falla crítica
        INSERT INTO public.maintenance_logs (
            asset_id, locked_by_uid, issue_description
        ) VALUES (
            NEW.asset_id, 
            NULL, -- SYSTEM BOT / TELEMETRY OVERRIDE
            '[AUTOMATED IOT LOCK] CRITICAL ENGINE OVERHEAT DETECTED: ' || NEW.coolant_temp_celsius || '°C'
        );
        
        -- 2. Cambiar el estado del activo
        UPDATE public.assets 
        SET status = 'maintenance' 
        WHERE id = NEW.asset_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_iot_safety_check ON public.telemetry_logs;
CREATE TRIGGER trg_iot_safety_check
AFTER INSERT ON public.telemetry_logs
FOR EACH ROW
EXECUTE FUNCTION public.process_telemetry_safety_override();
