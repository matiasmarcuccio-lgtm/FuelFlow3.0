CREATE OR REPLACE FUNCTION check_insurance_compliance()
RETURNS TRIGGER AS $$
DECLARE
    v_target_id UUID;
BEGIN
    v_target_id := COALESCE(NEW.driver_id, NEW.contractor_id);
    
    -- Utilizando IS NOT TRUE para manejar NULL de forma estricta
    IF (SELECT insurance_expiry_date > CURRENT_DATE FROM public.profiles WHERE id = v_target_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Operación bloqueada: Póliza expirada. Suba su documentación en la sección de cumplimiento.';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
