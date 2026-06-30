-- Asegurarnos de que RLS esté activo en la tabla (por si no lo estaba)
ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;

-- Borrar políticas si existen previamente para evitar conflictos
DROP POLICY IF EXISTS "Protect Asset Insertions by Fleet" ON public.assets;
DROP POLICY IF EXISTS "Protect Asset Reads by Fleet" ON public.assets;
DROP POLICY IF EXISTS "Protect Asset Updates by Fleet" ON public.assets;
DROP POLICY IF EXISTS "Protect Asset Deletions by Fleet" ON public.assets;

-- Crear el candado criptográfico en la INSERCIÓN
CREATE POLICY "Protect Asset Insertions by Fleet"
ON public.assets
FOR INSERT
WITH CHECK (
  fleet_id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid())
);

-- Crear el candado criptográfico en la LECTURA
CREATE POLICY "Protect Asset Reads by Fleet"
ON public.assets
FOR SELECT
USING (
  fleet_id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid())
);

-- Crear el candado criptográfico en la ACTUALIZACIÓN
CREATE POLICY "Protect Asset Updates by Fleet"
ON public.assets
FOR UPDATE
USING (
  fleet_id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid())
);

-- Crear el candado criptográfico en el BORRADO
CREATE POLICY "Protect Asset Deletions by Fleet"
ON public.assets
FOR DELETE
USING (
  fleet_id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid())
);
