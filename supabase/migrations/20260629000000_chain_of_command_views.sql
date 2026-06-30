-- Migración de la Cadena de Mando Militar (Dictador, Despachador, Ejecutor, Fantasma)

-- 1. BUILDER VIEWS (El Dictador)
CREATE OR REPLACE VIEW public.view_project_progress AS
SELECT 
  material_type,
  COUNT(id) as total_trips,
  SUM(COALESCE(ocr_mass_extracted, loaded_gross_mass)) as total_mass_delivered_kg
FROM public.load_offers
WHERE status = 'COMPLETED'
GROUP BY material_type;

CREATE OR REPLACE VIEW public.view_site_bottlenecks AS
SELECT 
  staging_area as geofence_zone,
  COUNT(id) as active_trucks,
  AVG(EXTRACT(EPOCH FROM (completed_at_local - created_at))/60) as avg_cycle_time_mins
FROM public.load_offers
WHERE status IN ('LOADING', 'IN_TRANSIT')
GROUP BY staging_area;

-- 2. FLEET MANAGER VIEWS & FUNCTIONS (El Despachador)
CREATE OR REPLACE VIEW public.view_driver_fatigue AS
SELECT 
  a.operator_id as driver_id,
  MIN(lo.created_at) as shift_start,
  EXTRACT(EPOCH FROM (NOW() - MIN(lo.created_at)))/3600 as hours_active,
  COUNT(lo.id) as trips_today
FROM public.assignments a
JOIN public.load_offers lo ON a.load_offer_id = lo.id
WHERE lo.created_at > CURRENT_DATE
GROUP BY a.operator_id;

CREATE OR REPLACE VIEW public.view_fleet_matrix AS
SELECT 
  v.id as vehicle_id,
  v.registration_number,
  v.has_4x4_traction,
  v.turning_radius_m,
  v.max_payload_kg
FROM public.assets v
WHERE v.is_active = true;

CREATE OR REPLACE FUNCTION public.fn_assign_asset_to_project(p_load_offer_id UUID, p_driver_id UUID, p_asset_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_fatigue_hours NUMERIC;
  v_needs_4x4 BOOLEAN;
  v_max_radius NUMERIC;
  v_asset_4x4 BOOLEAN;
  v_asset_radius NUMERIC;
BEGIN
  -- 1. Fatigue Check
  SELECT hours_active INTO v_fatigue_hours FROM view_driver_fatigue WHERE driver_id = p_driver_id;
  IF v_fatigue_hours > 11 THEN
    RAISE EXCEPTION 'NHVR Fatigue Limit Exceeded: Driver has been active for over 11 hours.';
  END IF;

  -- 2. Terrain Compatibility Check
  SELECT requires_4x4_traction, max_turn_radius_m INTO v_needs_4x4, v_max_radius FROM load_offers WHERE id = p_load_offer_id;
  SELECT has_4x4_traction, turning_radius_m INTO v_asset_4x4, v_asset_radius FROM assets WHERE id = p_asset_id;

  IF v_needs_4x4 = true AND v_asset_4x4 = false THEN
    RAISE EXCEPTION 'Terrain Restriction: Project requires 4x4 traction.';
  END IF;

  IF v_asset_radius > v_max_radius THEN
    RAISE EXCEPTION 'Space Restriction: Vehicle turning radius exceeds project limits.';
  END IF;

  -- 3. Assign
  INSERT INTO assignments (load_offer_id, operator_id, assigned_at) VALUES (p_load_offer_id, p_driver_id, NOW());
  UPDATE load_offers SET status = 'PENDING' WHERE id = p_load_offer_id;
  
  RETURN TRUE;
END;
$$;

-- 3. INSPECTOR VIEW (El Fantasma)
CREATE OR REPLACE VIEW public.view_cor_audit_timeline AS
SELECT 
  lo.id as load_id,
  lo.created_at,
  lo.completed_at_local as resolved_at,
  lo.status,
  lo.anomaly_flag,
  lo.anomaly_resolution_tags,
  lo.anomaly_resolution_reason,
  a.operator_id
FROM public.load_offers lo
LEFT JOIN public.assignments a ON lo.id = a.load_offer_id
WHERE lo.anomaly_flag IS NOT NULL OR lo.status = 'BREAKDOWN'
ORDER BY lo.created_at DESC;

-- Fix RLS vulnerability on assignments
ALTER TABLE public.assignments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow fleet manager to assign"
  ON public.assignments FOR ALL TO authenticated USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('FLEET_MANAGER', 'SUPER_ADMIN'))
  );

CREATE POLICY "Allow driver to see own assignments"
  ON public.assignments FOR SELECT TO authenticated USING (
    operator_id = auth.uid()
  );

-- Secure the views based on roles
-- Note: Views typically run with the permissions of the view creator, but we can secure access to them via RLS on underlying tables or by revoking public access.
-- We'll rely on the frontend restricting access to the dashboards, and the underlying RLS policies protecting the raw data.
