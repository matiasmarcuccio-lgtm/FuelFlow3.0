-- 1. Alinear tabla fleets
ALTER TABLE public.fleets ADD COLUMN IF NOT EXISTS grace_period_until TIMESTAMPTZ;

-- 2. Alinear tabla fleet_billing_ledger con la sintaxis del Emisor Nocturno
ALTER TABLE public.fleet_billing_ledger RENAME COLUMN recorded_date TO billing_date;
ALTER TABLE public.fleet_billing_ledger ADD COLUMN IF NOT EXISTS stripe_reported BOOLEAN DEFAULT false;

-- Actualizar la función del cron para usar el nuevo nombre de columna
CREATE OR REPLACE FUNCTION public.fn_capture_daily_fleet_usage()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_fleet record;
    v_count int;
BEGIN
    FOR v_fleet IN SELECT id FROM public.fleets LOOP
        SELECT COUNT(*) INTO v_count
        FROM public.assets
        WHERE fleet_id = v_fleet.id AND status = 'operational';

        INSERT INTO public.fleet_billing_ledger (fleet_id, billing_date, active_asset_count)
        VALUES (v_fleet.id, CURRENT_DATE, v_count)
        ON CONFLICT (fleet_id, billing_date) 
        DO UPDATE SET active_asset_count = EXCLUDED.active_asset_count;
    END LOOP;
    
    PERFORM net.http_post(
        url := current_setting('app.settings.edge_function_base_url', true) || '/report-usage',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
        ),
        body := '{}'::jsonb
    );
END;
$$;

-- 3. Crear o alinear project_sites para la Bóveda Pasiva Legal
CREATE TABLE IF NOT EXISTS public.project_sites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fleet_id UUID REFERENCES public.fleets(id) NOT NULL,
    name VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'ACTIVE',
    vault_status VARCHAR(50) DEFAULT 'OPERATIONAL',
    purge_scheduled_for TIMESTAMPTZ
);
-- Si la tabla ya existía, añadimos las columnas
ALTER TABLE public.project_sites ADD COLUMN IF NOT EXISTS vault_status VARCHAR(50) DEFAULT 'OPERATIONAL';
ALTER TABLE public.project_sites ADD COLUMN IF NOT EXISTS purge_scheduled_for TIMESTAMPTZ;
