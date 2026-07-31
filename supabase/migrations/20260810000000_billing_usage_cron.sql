-- 1. Crear el ledger de facturación volumétrica (si no existe)
CREATE TABLE IF NOT EXISTS public.fleet_billing_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fleet_id UUID REFERENCES public.fleets(id) NOT NULL,
    recorded_date DATE NOT NULL DEFAULT CURRENT_DATE,
    active_asset_count INT NOT NULL DEFAULT 0,
    stripe_usage_record_id VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(fleet_id, recorded_date)
);

-- Habilitar RLS en la tabla del ledger
ALTER TABLE public.fleet_billing_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "SuperAdmins and Fleet Managers can view their volumetrics" ON public.fleet_billing_ledger;
CREATE POLICY "SuperAdmins and Fleet Managers can view their volumetrics"
    ON public.fleet_billing_ledger FOR SELECT
    USING (
        auth.uid() IN (
            SELECT id FROM public.profiles 
            WHERE role IN ('super_admin', 'fleet_manager')
        )
    );

-- 2. Función que fotografía el inventario operativo y dispara la emisión a Stripe
CREATE OR REPLACE FUNCTION public.fn_capture_daily_fleet_usage()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_fleet record;
    v_count int;
BEGIN
    -- A) Fotografiar a medianoche la cantidad exacta de vehículos operativos
    FOR v_fleet IN SELECT id FROM public.fleets LOOP
        SELECT COUNT(*) INTO v_count
        FROM public.assets
        WHERE fleet_id = v_fleet.id AND status = 'operational';

        -- Guardar en el ledger. Si ya se corrió hoy, actualiza el conteo.
        INSERT INTO public.fleet_billing_ledger (fleet_id, recorded_date, active_asset_count)
        VALUES (v_fleet.id, CURRENT_DATE, v_count)
        ON CONFLICT (fleet_id, recorded_date) 
        DO UPDATE SET active_asset_count = EXCLUDED.active_asset_count;
    END LOOP;
    
    -- B) Invocar a la Edge Function de Stripe vía pg_net de manera asíncrona
    -- net.http_post_bg es Fire-and-Forget
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

-- 3. Programar el cronógrafo para Hobart (23:55)
-- Nota: pg_cron utiliza hora UTC por defecto. Hobart (AEST) es UTC+10 (o +11 con DST).
-- Para simplificar, lo configuramos como un trigger diario genérico a las 13:55 UTC (23:55 AEST estándar).
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule(
    'daily_fleet_usage_snapshot',
    '55 13 * * *', 
    'SELECT public.fn_capture_daily_fleet_usage();'
);
