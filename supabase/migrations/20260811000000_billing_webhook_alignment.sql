-- 1. Añadir el colchón de 72 horas a las flotas
ALTER TABLE public.fleets ADD COLUMN IF NOT EXISTS grace_period_until TIMESTAMPTZ;

-- 2. Crear o alinear la tabla fleet_billing_ledger
CREATE TABLE IF NOT EXISTS public.fleet_billing_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fleet_id UUID REFERENCES public.fleets(id) NOT NULL,
    billing_date DATE NOT NULL DEFAULT CURRENT_DATE,
    active_asset_count INT NOT NULL DEFAULT 0,
    stripe_usage_record_id VARCHAR(255),
    stripe_reported BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(fleet_id, billing_date)
);

-- Si la tabla ya existía, nos aseguramos de que tenga las nuevas columnas 
-- (Ignorará el error si ya existen, debido a la cláusula IF NOT EXISTS)
ALTER TABLE public.fleet_billing_ledger ADD COLUMN IF NOT EXISTS billing_date DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE public.fleet_billing_ledger ADD COLUMN IF NOT EXISTS stripe_reported BOOLEAN DEFAULT false;

-- Habilitar RLS en la tabla del ledger (por si se acaba de crear)
ALTER TABLE public.fleet_billing_ledger ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'fleet_billing_ledger' AND policyname = 'SuperAdmins and Fleet Managers can view their volumetrics'
    ) THEN
        CREATE POLICY "SuperAdmins and Fleet Managers can view their volumetrics"
            ON public.fleet_billing_ledger FOR SELECT
            USING (
                auth.uid() IN (
                    SELECT id FROM public.profiles 
                    WHERE role IN ('super_admin', 'fleet_manager')
                )
            );
    END IF;
END
$$;

-- Actualizar la función del cron para usar el nuevo nombre de columna "billing_date"
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

-- Programar el cronógrafo para Hobart (23:55 AEST -> 13:55 UTC)
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule(
    'daily_fleet_usage_snapshot',
    '55 13 * * *', 
    'SELECT public.fn_capture_daily_fleet_usage();'
);

-- 3. Crear o alinear la tabla project_sites para la Bóveda Pasiva
CREATE TABLE IF NOT EXISTS public.project_sites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fleet_id UUID REFERENCES public.fleets(id) NOT NULL,
    name VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'ACTIVE',
    vault_status VARCHAR(50) DEFAULT 'OPERATIONAL',
    purge_scheduled_for TIMESTAMPTZ
);
ALTER TABLE public.project_sites ADD COLUMN IF NOT EXISTS vault_status VARCHAR(50) DEFAULT 'OPERATIONAL';
ALTER TABLE public.project_sites ADD COLUMN IF NOT EXISTS purge_scheduled_for TIMESTAMPTZ;
