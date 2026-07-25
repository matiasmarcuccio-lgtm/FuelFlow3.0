CREATE OR REPLACE FUNCTION public.fn_dispatch_shift(p_master_order_id uuid, p_driver_id uuid, p_asset_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
    'MANIFEST_PENDING',
    v_master_order.material_type,
    v_master_order.requires_4x4_traction,
    v_master_order.max_turn_radius_m,
    NOW()
  );

  RETURN v_shift_id;
END;
$function$;
