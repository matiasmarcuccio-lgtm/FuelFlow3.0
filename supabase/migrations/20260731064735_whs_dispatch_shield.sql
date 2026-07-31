-- ============================================================================
-- BLINDAJE WHS DEL DESPACHO TÁCTICO (CAPA 0)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_dispatch_shift(
    p_master_order_id UUID,
    p_driver_id UUID,
    p_asset_id UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_fleet_id UUID;
    v_asset_status VARCHAR;
    v_assignment_id UUID;
BEGIN
    -- 1. Extraer y validar la jurisdicción del despachador
    SELECT fleet_id INTO v_fleet_id FROM public.profiles WHERE id = auth.uid();
    IF v_fleet_id IS NULL THEN
        RAISE EXCEPTION 'Violación de Acceso: Jurisdicción corporativa no encontrada.';
    END IF;

    -- 2. Inspección forense del estado de la maquinaria
    SELECT status INTO v_asset_status 
    FROM public.assets 
    WHERE id = p_asset_id AND fleet_id = v_fleet_id;

    IF v_asset_status IS NULL THEN
        RAISE EXCEPTION 'Error de Jurisdicción: La máquina no existe en su flota.';
    END IF;

    -- El Candado WHS (Imposibilita asignar metal dañado)
    IF v_asset_status != 'OPERATIONAL' THEN
        RAISE EXCEPTION 'Violación WHS (Error 42501): Prohibido despachar maquinaria en estado %', v_asset_status;
    END IF;

    -- 3. Inserción Atómica del Turno (Asumiendo que tu tabla es asset_assignments)
    INSERT INTO public.asset_assignments (master_order_id, driver_id, asset_id, fleet_id, status)
    VALUES (p_master_order_id, p_driver_id, p_asset_id, v_fleet_id, 'DISPATCHED')
    RETURNING id INTO v_assignment_id;

    RETURN v_assignment_id;
END;
$$;
