-- Migración: Esquema Logístico y Forense de Activos (FuelFlow 3.0)

-- Limpieza de tabla legacy
DROP TABLE IF EXISTS public.assets CASCADE;

-- 1. Tipos de Datos (ENUMs Físicos)
CREATE TYPE public.asset_category AS ENUM ('heavy_machinery', 'light_vehicle', 'static_plant');
CREATE TYPE public.asset_status AS ENUM ('operational', 'maintenance', 'decommissioned');

-- 2. Tabla de Categorías de Licencia (Catálogo Legal Estricto)
CREATE TABLE public.license_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(50) UNIQUE NOT NULL, -- ej. 'HR' (Heavy Rigid), 'LF' (Forklift)
    description TEXT NOT NULL
);

-- 3. Tabla Maestra de Activos
CREATE TABLE public.assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fleet_id UUID NOT NULL REFERENCES public.fleets(id) ON DELETE CASCADE,
    internal_code VARCHAR(100) NOT NULL,
    category asset_category NOT NULL,
    status asset_status DEFAULT 'operational' NOT NULL,
    current_engine_hours DECIMAL(10,2),
    current_odometer DECIMAL(10,2),
    required_license_id UUID NOT NULL REFERENCES public.license_categories(id),
    
    -- El Blindaje Físico y Telemétrico
    CONSTRAINT chk_telemetry_match CHECK (
        (category = 'heavy_machinery' AND current_engine_hours IS NOT NULL) OR 
        (category = 'light_vehicle' AND current_odometer IS NOT NULL) OR
        (category = 'static_plant')
    ),
    
    -- Prevenir códigos duplicados dentro de la misma flota
    CONSTRAINT uq_fleet_internal_code UNIQUE (fleet_id, internal_code)
);

-- 4. El Candado Financiero de Costo Cero (RLS de Memoria JWT)
ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Enforce JWT Financial Lockdown on Assets" ON public.assets
FOR ALL
USING (
    fleet_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'fleet_id')::uuid
    AND 
    (current_setting('request.jwt.claims', true)::jsonb ->> 'subscription_status') IN ('active', 'trialing')
);
