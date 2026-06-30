-- Inyección de Caos (Red Teaming)

DO $$
DECLARE
  v_offer RECORD;
  v_count INT := 0;
BEGIN
  -- 5 BREAKDOWNS
  FOR v_offer IN (SELECT id FROM load_offers WHERE status = 'PENDING' OR status = 'LOADING' LIMIT 5)
  LOOP
    UPDATE load_offers SET status = 'BREAKDOWN' WHERE id = v_offer.id;
    v_count := v_count + 1;
  END LOOP;

  -- 5 EMERGENCY OVERRIDES
  FOR v_offer IN (SELECT id FROM load_offers WHERE status = 'PENDING' OR status = 'LOADING' AND id NOT IN (SELECT id FROM load_offers WHERE status = 'BREAKDOWN') LIMIT 5)
  LOOP
    UPDATE load_offers SET status = 'IN_TRANSIT', anomaly_flag = 'DRIVER_EMERGENCY_OVERRIDE' WHERE id = v_offer.id;
    v_count := v_count + 1;
  END LOOP;

  -- 5 MASS MISMATCHES (Triggered by ending in 9 via the DB trigger)
  FOR v_offer IN (SELECT id FROM load_offers WHERE status = 'PENDING' OR status = 'LOADING' AND anomaly_flag IS NULL AND status != 'BREAKDOWN' LIMIT 5)
  LOOP
    UPDATE load_offers SET status = 'IN_TRANSIT', loaded_gross_mass = 48009, docket_image_path = 'mock_chaos_image.jpg' WHERE id = v_offer.id;
    v_count := v_count + 1;
  END LOOP;
  
  RAISE NOTICE '🌪️ Chaos Injection Complete! % anomalies created.', v_count;
END $$;
