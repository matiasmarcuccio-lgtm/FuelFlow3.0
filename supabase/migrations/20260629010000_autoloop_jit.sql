-- Migración: Motor JIT de Bucle Continuo (Auto-Loop)

-- 1. Master Orders (Las tuberías abiertas por el Constructor)
CREATE TABLE IF NOT EXISTS public.master_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    material_type VARCHAR NOT NULL,
    target_tonnage NUMERIC NOT NULL,
    origin_geofence JSONB NOT NULL,
    destination_geofence JSONB NOT NULL,
    requires_4x4_traction BOOLEAN DEFAULT false,
    max_turn_radius_m NUMERIC DEFAULT 15.0,
    status VARCHAR DEFAULT 'OPEN', -- 'OPEN', 'FULFILLED'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id)
);

ALTER TABLE public.master_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Builders can create master orders" ON public.master_orders FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('BUILDER', 'SUPER_ADMIN')));
CREATE POLICY "Everyone can view master orders" ON public.master_orders FOR SELECT TO authenticated USING (true);
CREATE POLICY "Builders can update master orders" ON public.master_orders FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('BUILDER', 'SUPER_ADMIN')));

-- 2. Shift Assignments (El acople de activos a las tuberías por el Despachador)
CREATE TABLE IF NOT EXISTS public.shift_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    master_order_id UUID REFERENCES public.master_orders(id),
    driver_id UUID REFERENCES auth.users(id),
    vehicle_id UUID REFERENCES public.assets(id),
    status VARCHAR DEFAULT 'ACTIVE', -- 'ACTIVE', 'COMPLETED', 'SUSPENDED_FATIGUE'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    assigned_by UUID REFERENCES auth.users(id)
);

ALTER TABLE public.shift_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Fleet managers can create shift assignments" ON public.shift_assignments FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('FLEET_MANAGER', 'SUPER_ADMIN')));
CREATE POLICY "Everyone can view shift assignments" ON public.shift_assignments FOR SELECT TO authenticated USING (true);
CREATE POLICY "Fleet managers can update shift assignments" ON public.shift_assignments FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('FLEET_MANAGER', 'SUPER_ADMIN')));

-- Add master_order_id to load_offers to track the pipeline
ALTER TABLE public.load_offers ADD COLUMN IF NOT EXISTS master_order_id UUID REFERENCES public.master_orders(id);
ALTER TABLE public.load_offers ADD COLUMN IF NOT EXISTS driver_id UUID REFERENCES auth.users(id);

-- 3. Función Auto-Loop JIT
CREATE OR REPLACE FUNCTION public.fn_trigger_autoloop()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_shift_assignment RECORD;
  v_master_order RECORD;
  v_total_delivered NUMERIC;
BEGIN
  -- Solo evaluar cuando una oferta pasa a COMPLETED
  IF NEW.status = 'COMPLETED' AND OLD.status != 'COMPLETED' THEN
    
    -- Si la oferta pertenece a un Master Order
    IF NEW.master_order_id IS NOT NULL THEN
      
      -- Buscar la asignación de turno ACTIVA para este conductor
      SELECT * INTO v_shift_assignment 
      FROM public.shift_assignments 
      WHERE driver_id = NEW.driver_id AND status = 'ACTIVE' AND master_order_id = NEW.master_order_id
      LIMIT 1;

      IF FOUND THEN
        -- Obtener detalles del Master Order
        SELECT * INTO v_master_order FROM public.master_orders WHERE id = NEW.master_order_id;
        
        -- Calcular tonelaje entregado total para esta orden
        SELECT COALESCE(SUM(COALESCE(ocr_mass_extracted, loaded_gross_mass)), 0) INTO v_total_delivered 
        FROM public.load_offers 
        WHERE master_order_id = NEW.master_order_id AND status = 'COMPLETED';

        -- Si no se ha alcanzado la meta, generar el siguiente ciclo
        IF v_total_delivered < v_master_order.target_tonnage THEN
          INSERT INTO public.load_offers (
            master_order_id,
            driver_id,
            status,
            material_type,
            requires_4x4_traction,
            max_turn_radius_m,
            created_at
          ) VALUES (
            v_master_order.id,
            NEW.driver_id,
            'PENDING', -- Generado automáticamente
            v_master_order.material_type,
            v_master_order.requires_4x4_traction,
            v_master_order.max_turn_radius_m,
            NOW()
          );
        ELSE
          -- Cerrar el Master Order y los Turnos
          UPDATE public.master_orders SET status = 'FULFILLED' WHERE id = v_master_order.id;
          UPDATE public.shift_assignments SET status = 'COMPLETED' WHERE master_order_id = v_master_order.id;
        END IF;
      END IF;
    END IF;
  END IF;

  -- Romper el bucle si hay avería
  IF NEW.status = 'BREAKDOWN' THEN
    UPDATE public.shift_assignments SET status = 'SUSPENDED_BREAKDOWN' WHERE driver_id = NEW.driver_id AND status = 'ACTIVE';
  END IF;

  RETURN NEW;
END;
$$;

-- Vincular el Trigger
DROP TRIGGER IF EXISTS trg_autoloop_on_complete ON public.load_offers;
CREATE TRIGGER trg_autoloop_on_complete
AFTER UPDATE ON public.load_offers
FOR EACH ROW
EXECUTE FUNCTION public.fn_trigger_autoloop();

-- Función para iniciar el bucle (Llamada por el Fleet Manager)
CREATE OR REPLACE FUNCTION public.fn_dispatch_shift(p_master_order_id UUID, p_driver_id UUID, p_asset_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_fatigue_hours NUMERIC;
  v_shift_id UUID;
  v_master_order RECORD;
  v_asset RECORD;
BEGIN
  -- 1. Fatigue Check
  SELECT hours_active INTO v_fatigue_hours FROM view_driver_fatigue WHERE driver_id = p_driver_id;
  IF v_fatigue_hours > 11 THEN
    RAISE EXCEPTION 'NHVR Fatigue Limit Exceeded: Driver has been active for over 11 hours.';
  END IF;

  -- 2. Traer master order
  SELECT * INTO v_master_order FROM public.master_orders WHERE id = p_master_order_id;
  IF NOT FOUND OR v_master_order.status != 'OPEN' THEN
    RAISE EXCEPTION 'Master Order not found or not open.';
  END IF;

  -- 3. Terrain Check
  SELECT * INTO v_asset FROM public.assets WHERE id = p_asset_id;
  IF v_master_order.requires_4x4_traction = true AND v_asset.has_4x4_traction = false THEN
    RAISE EXCEPTION 'Terrain Restriction: Project requires 4x4 traction.';
  END IF;

  -- 4. Crear Asignación de Turno
  INSERT INTO public.shift_assignments (master_order_id, driver_id, vehicle_id, assigned_by) 
  VALUES (p_master_order_id, p_driver_id, p_asset_id, auth.uid())
  RETURNING id INTO v_shift_id;

  -- 5. Generar la PRIMERA Load Offer del bucle
  INSERT INTO public.load_offers (
    master_order_id,
    driver_id,
    status,
    material_type,
    requires_4x4_traction,
    max_turn_radius_m,
    created_at
  ) VALUES (
    v_master_order.id,
    p_driver_id,
    'PENDING',
    v_master_order.material_type,
    v_master_order.requires_4x4_traction,
    v_master_order.max_turn_radius_m,
    NOW()
  );

  RETURN v_shift_id;
END;
$$;
