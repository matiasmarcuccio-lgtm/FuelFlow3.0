BEGIN;

-- 1. Asegurar que la tabla existe y tiene el esquema de control logístico
CREATE TABLE IF NOT EXISTS public.assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fleet_id UUID NOT NULL REFERENCES public.fleets(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL CHECK (category IN ('dump_truck', 'excavator', 'loader', 'dozer', 'water_cart', 'weighbridge')),
    status VARCHAR(50) NOT NULL DEFAULT 'OPERATIONAL' CHECK (status IN ('OPERATIONAL', 'MAINTENANCE', 'OUT_OF_SERVICE')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;

-- 2. Escudo de Lectura: La tripulación solo puede ver máquinas de su propia cantera
DROP POLICY IF EXISTS "Tripulación ve su propia maquinaria" ON public.assets;
CREATE POLICY "Tripulación ve su propia maquinaria" ON public.assets
FOR SELECT TO authenticated USING (
    fleet_id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid())
);

-- 3. Escudo de Inserción: Solo Dueños y Gerentes pueden comprar/registrar metal
DROP POLICY IF EXISTS "Solo gerencia matricula maquinaria" ON public.assets;
CREATE POLICY "Solo gerencia matricula maquinaria" ON public.assets
FOR INSERT TO authenticated WITH CHECK (
    fleet_id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid()) AND
    (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('account_owner', 'fleet_manager')
);

-- 4. Escudo de Actualización: Para cuando conectemos el Fitter Portal
DROP POLICY IF EXISTS "Actualización por gerencia o mecánicos" ON public.assets;
CREATE POLICY "Actualización por gerencia o mecánicos" ON public.assets
FOR UPDATE TO authenticated USING (
    fleet_id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid()) AND
    (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('account_owner', 'fleet_manager', 'fitter')
);

COMMIT;
