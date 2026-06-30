-- Simplify the RPC so mobile doesn't need to pass the shift ID
CREATE OR REPLACE FUNCTION public.fn_request_detach(p_reason VARCHAR) 
RETURNS VOID 
LANGUAGE plpgsql 
SECURITY DEFINER 
AS $$ 
BEGIN 
  UPDATE public.shift_assignments 
  SET intent_to_detach = true, detach_reason = p_reason 
  WHERE driver_id = auth.uid() AND status = 'ACTIVE'; 
END; 
$$;
