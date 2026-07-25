DO $$
DECLARE 
    new_id UUID := gen_random_uuid(); 
    v_raw_fleet UUID; 
BEGIN 
    INSERT INTO public.fleets (name, status, tier) 
    VALUES ('Test Flota', 'past_due', 'basic') 
    RETURNING id INTO v_raw_fleet; 

    INSERT INTO public.profiles (id, role, fleet_id, full_name, created_at, updated_at) 
    VALUES (new_id, 'fleet_manager', v_raw_fleet, 'Test', now(), now()); 
END; 
$$;
