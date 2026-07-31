BEGIN;

-- 1. EL CANDADO FÍSICO (Aplicar LOTO)
CREATE OR REPLACE FUNCTION public.fitter_lock_asset(
    p_asset_id UUID,
    p_description TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_fleet_id UUID;
    v_defect_id UUID;
BEGIN
    -- Validar jurisdicción y rol
    SELECT fleet_id INTO v_fleet_id FROM public.profiles 
    WHERE id = auth.uid() AND role IN ('fitter', 'fleet_manager', 'account_owner');
    
    IF v_fleet_id IS NULL THEN
        RAISE EXCEPTION 'Violación de Acceso: No posee credenciales de mantenimiento.';
    END IF;

    -- Validar que el activo pertenece a la flota y está operativo
    IF NOT EXISTS (SELECT 1 FROM public.assets WHERE id = p_asset_id AND fleet_id = v_fleet_id AND status = 'OPERATIONAL') THEN
        RAISE EXCEPTION 'Violación WHS: Activo no encontrado en su jurisdicción o ya se encuentra inmovilizado.';
    END IF;

    -- Mutación atómica: Bloquear maquinaria
    UPDATE public.assets SET status = 'MAINTENANCE' WHERE id = p_asset_id;

    -- Rastro forense: Registrar el defecto
    INSERT INTO public.plant_defects (asset_id, reported_by, defect_description, status)
    VALUES (p_asset_id, auth.uid(), p_description, 'OPEN')
    RETURNING id INTO v_defect_id;

    RETURN v_defect_id;
END;
$$;

-- 2. LA LLAVE DE LIBERACIÓN (Levantar LOTO)
CREATE OR REPLACE FUNCTION public.fitter_release_asset(
    p_asset_id UUID,
    p_resolution_notes TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_fleet_id UUID;
    v_defect_id UUID;
BEGIN
    -- Validar jurisdicción y rol
    SELECT fleet_id INTO v_fleet_id FROM public.profiles 
    WHERE id = auth.uid() AND role IN ('fitter', 'fleet_manager', 'account_owner');
    
    IF v_fleet_id IS NULL THEN
        RAISE EXCEPTION 'Violación de Acceso: No posee credenciales de mantenimiento.';
    END IF;

    -- Buscar el defecto abierto para este activo
    SELECT id INTO v_defect_id FROM public.plant_defects 
    WHERE asset_id = p_asset_id AND status = 'OPEN' 
    ORDER BY created_at DESC LIMIT 1;

    IF v_defect_id IS NULL THEN
        RAISE EXCEPTION 'Violación Forense: No existe un reporte de defecto abierto para esta máquina.';
    END IF;

    -- Mutación atómica: Cerrar el defecto y liberar maquinaria
    UPDATE public.plant_defects 
    SET status = 'RESOLVED', resolution_notes = p_resolution_notes, rectified_at = NOW() 
    WHERE id = v_defect_id;

    UPDATE public.assets SET status = 'OPERATIONAL' WHERE id = p_asset_id;

    RETURN TRUE;
END;
$$;

COMMIT;
