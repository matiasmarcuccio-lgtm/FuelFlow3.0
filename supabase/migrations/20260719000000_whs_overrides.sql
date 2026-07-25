CREATE TABLE IF NOT EXISTS public.whs_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supervisor_id UUID NOT NULL REFERENCES public.profiles(id),
    driver_id UUID NOT NULL REFERENCES public.profiles(id),
    document_path TEXT NOT NULL,
    new_expiry_date DATE NOT NULL,
    override_timestamp TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.whs_overrides ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION fn_verify_driver_insurance(p_driver_id UUID, p_expiry_date DATE, p_file_path TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_role VARCHAR;
BEGIN
    SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();
    IF v_role NOT IN ('supervisor', 'fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'UNAUTHORIZED_WHS_OVERRIDE: You do not have the required authority level.';
    END IF;

    INSERT INTO public.whs_overrides (supervisor_id, driver_id, document_path, new_expiry_date, override_timestamp)
    VALUES (auth.uid(), p_driver_id, p_file_path, p_expiry_date, now());

    UPDATE public.profiles
    SET insurance_expiry_date = p_expiry_date
    WHERE id = p_driver_id;

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
