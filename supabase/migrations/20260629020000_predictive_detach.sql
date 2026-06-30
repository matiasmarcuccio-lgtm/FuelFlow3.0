-- Migración: Cierre Amable y Matemática Predictiva Híbrida

-- 1. Ampliación de la tabla shift_assignments
ALTER TABLE public.shift_assignments 
ADD COLUMN IF NOT EXISTS intent_to_detach BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS detach_reason VARCHAR;

-- 2. Función RPC para que el móvil notifique la intención de desacople
CREATE OR REPLACE FUNCTION public.fn_request_detach(p_shift_id UUID, p_reason VARCHAR)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.shift_assignments 
  SET intent_to_detach = true, detach_reason = p_reason
  WHERE id = p_shift_id AND driver_id = auth.uid() AND status = 'ACTIVE';
END;
$$;

-- 3. Reescribir el Trigger Auto-Loop para inyectar Matemática Predictiva Híbrida
CREATE OR REPLACE FUNCTION public.fn_trigger_autoloop()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_shift_assignment RECORD;
  v_master_order RECORD;
  v_total_delivered NUMERIC;
  v_projected_tonnage NUMERIC;
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
        -- VERIFICACIÓN DE CIERRE AMABLE (Graceful Shutdown)
        IF v_shift_assignment.intent_to_detach = true THEN
          -- El conductor solicitó salir. Cerramos su turno y abortamos la inyección del siguiente ciclo.
          UPDATE public.shift_assignments SET status = 'COMPLETED' WHERE id = v_shift_assignment.id;
          RETURN NEW;
        END IF;

        -- Obtener detalles del Master Order
        SELECT * INTO v_master_order FROM public.master_orders WHERE id = NEW.master_order_id;
        
        -- Calcular tonelaje histórico ya entregado
        SELECT COALESCE(SUM(COALESCE(ocr_mass_extracted, loaded_gross_mass)), 0) INTO v_total_delivered 
        FROM public.load_offers 
        WHERE master_order_id = NEW.master_order_id AND status = 'COMPLETED';

        -- Calcular tonelaje predictivo híbrido de la flota en movimiento
        SELECT 
          COALESCE(SUM(
            CASE 
              WHEN lo.status = 'IN_TRANSIT' THEN COALESCE(lo.loaded_gross_mass, a.max_payload_kg)
              ELSE a.max_payload_kg
            END
          ), 0) INTO v_projected_tonnage
        FROM public.load_offers lo
        JOIN public.shift_assignments sa ON sa.driver_id = lo.driver_id AND sa.master_order_id = lo.master_order_id AND sa.status = 'ACTIVE'
        JOIN public.assets a ON a.id = sa.vehicle_id
        WHERE lo.master_order_id = NEW.master_order_id 
          AND lo.status IN ('PENDING', 'MANIFEST_PENDING', 'IN_TRANSIT');

        -- Si la suma (Histórico + Predictivo) no alcanza la meta, inyectar nuevo ciclo
        IF (v_total_delivered + v_projected_tonnage) < v_master_order.target_tonnage THEN
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
            'PENDING', 
            v_master_order.material_type,
            v_master_order.requires_4x4_traction,
            v_master_order.max_turn_radius_m,
            NOW()
          );
        ELSE
          -- Si la tubería se llenó (o se proyecta llena), cerrarla
          UPDATE public.master_orders SET status = 'FULFILLED' WHERE id = v_master_order.id;
          -- Note: Los demás conductores terminarán sus viajes y al completar, no se les asignarán nuevos debido al target alcanzado.
          -- Los turnos se cerrarán solos a medida que terminan, o el despachador los libera.
          UPDATE public.shift_assignments SET status = 'COMPLETED' WHERE id = v_shift_assignment.id;
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
