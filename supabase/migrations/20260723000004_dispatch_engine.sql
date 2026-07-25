-- Migración: Motor de Despacho y Fatiga WHS (FuelFlow 3.0)

-- 1. Habilitar extensión btree_gist para restricciones de rango temporal
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 2. Catálogo de Acreditaciones (driver_licenses)
CREATE TABLE public.driver_licenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    license_category_id UUID NOT NULL REFERENCES public.license_categories(id) ON DELETE RESTRICT,
    issued_date DATE NOT NULL,
    expiry_date DATE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    
    CONSTRAINT chk_license_dates CHECK (issued_date < expiry_date)
);

-- 3. Centro de Gravedad Logístico: Asignaciones (asset_assignments)
CREATE TABLE public.asset_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fleet_id UUID NOT NULL REFERENCES public.fleets(id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES public.assets(id) ON DELETE CASCADE,
    driver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    assigned_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    shift_start TIMESTAMPTZ NOT NULL DEFAULT now(),
    shift_end TIMESTAMPTZ, -- Nulo si el turno está en curso
    fatigue_override_reason TEXT,
    override_approved_by UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ DEFAULT now(),
    
    CONSTRAINT chk_shift_dates CHECK (shift_start < shift_end OR shift_end IS NULL)
);

-- 4. El Control de Concurrencia (GiST): Prevención Matemática de Conflictos
-- Regla: Un activo NO puede estar asignado a dos personas en rangos superpuestos.
ALTER TABLE public.asset_assignments
ADD CONSTRAINT exclude_overlapping_asset_shifts
EXCLUDE USING gist (
    asset_id WITH =,
    tstzrange(shift_start, COALESCE(shift_end, 'infinity'::timestamptz)) WITH &&
);

-- Regla: Un conductor NO puede operar dos activos distintos en rangos superpuestos.
ALTER TABLE public.asset_assignments
ADD CONSTRAINT exclude_overlapping_driver_shifts
EXCLUDE USING gist (
    driver_id WITH =,
    tstzrange(shift_start, COALESCE(shift_end, 'infinity'::timestamptz)) WITH &&
);

-- 5. Motor de Intercepción: Validaciones Jurídicas WHS (Licencia y Fatiga)
CREATE OR REPLACE FUNCTION public.trg_validate_dispatch()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_req_license UUID;
    v_has_license BOOLEAN;
    v_total_hours NUMERIC;
    v_asset_status asset_status;
BEGIN
    -- A. Validar que el activo existe y está operativo
    SELECT required_license_id, status INTO v_req_license, v_asset_status
    FROM public.assets
    WHERE id = NEW.asset_id;

    IF v_asset_status != 'operational' THEN
        RAISE EXCEPTION 'WHS_ASSET_NOT_OPERATIONAL: Cannot assign an asset in % state.', v_asset_status;
    END IF;

    -- B. Validar Licencia del Conductor en tiempo real
    SELECT EXISTS (
        SELECT 1 FROM public.driver_licenses
        WHERE driver_id = NEW.driver_id
          AND license_category_id = v_req_license
          AND expiry_date >= CURRENT_DATE
    ) INTO v_has_license;

    IF NOT v_has_license THEN
        RAISE EXCEPTION 'WHS_INVALID_LICENSE: Driver lacks a valid unexpired license for this asset category.';
    END IF;

    -- C. Validación Dinámica de Fatiga (El Muro Permeable)
    -- Sumamos las horas de todos los turnos en las últimas 24 horas para este conductor
    SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (COALESCE(shift_end, now()) - shift_start)) / 3600), 0)
    INTO v_total_hours
    FROM public.asset_assignments
    WHERE driver_id = NEW.driver_id
      AND shift_start >= now() - INTERVAL '24 hours'
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

    -- Límite WHS: 12 horas acumuladas.
    IF v_total_hours >= 12 THEN
        -- Si no hay justificación escrita, se aborta irrevocablemente la transacción
        IF NEW.fatigue_override_reason IS NULL OR TRIM(NEW.fatigue_override_reason) = '' THEN
            RAISE EXCEPTION 'WHS_FATIGUE_LIMIT: Driver accumulated % hours in 24h (>12h). Auditable override reason required.', ROUND(v_total_hours, 1);
        END IF;
        
        -- Si hay justificación, forzamos que quede sellada por quien aprueba
        IF NEW.override_approved_by IS NULL THEN
            NEW.override_approved_by := NEW.assigned_by;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_before_dispatch
BEFORE INSERT OR UPDATE ON public.asset_assignments
FOR EACH ROW EXECUTE FUNCTION public.trg_validate_dispatch();

-- 6. El Candado Financiero de Costo Cero en el Despacho
ALTER TABLE public.asset_assignments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Enforce JWT Financial Lockdown on Dispatch" ON public.asset_assignments
FOR ALL
USING (
    fleet_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'fleet_id')::uuid
    AND 
    (current_setting('request.jwt.claims', true)::jsonb ->> 'subscription_status') IN ('active', 'trialing')
);
