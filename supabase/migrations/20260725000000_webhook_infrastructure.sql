-- Migración: Infraestructura de Webhooks B2B (Capa de Suscripción)

-- 1. Tabla de Destinos (Suscripciones aisladas por Flota)
CREATE TABLE public.webhook_endpoints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fleet_id UUID NOT NULL REFERENCES public.fleets(id) ON DELETE CASCADE,
    event_type VARCHAR(100) NOT NULL, -- ej: 'asset.locked.critical', 'whs.fatigue.breach'
    target_url TEXT NOT NULL,
    auth_secret TEXT, -- Firma criptográfica (HMAC) para que el cliente valide que el POST proviene de FuelFlow
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Restricción de Duplicidad
-- Previene que un gerente dispare dos veces el mismo payload a la misma URL de n8n o Make
ALTER TABLE public.webhook_endpoints
ADD CONSTRAINT uq_fleet_event_url UNIQUE (fleet_id, event_type, target_url);

-- 3. Aislamiento Criptográfico (El Candado JWT)
-- Ningún usuario podrá ver o alterar los webhooks de otra empresa minera
ALTER TABLE public.webhook_endpoints ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Enforce JWT Lockdown on Webhooks" ON public.webhook_endpoints
FOR ALL
USING (
    fleet_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'fleet_id')::uuid
);
