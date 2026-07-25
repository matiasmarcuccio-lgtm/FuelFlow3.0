-- 1. TABLA DE MATERIALES Y DENSIDADES INDUSTRIALES
CREATE TABLE IF NOT EXISTS public.materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fleet_id UUID NOT NULL,
    name VARCHAR(50) NOT NULL, -- Ej: 'GRAVA FINO', 'ESTÉRIL', 'MINERAL DE HIERRO'
    density_kg_m3 NUMERIC(6,2) NOT NULL, -- Ej: 1800.00 kg/m3 para grava
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. TABLA DE RUTAS OPERATIVAS Y ZONAS DE DESCARGA
CREATE TABLE IF NOT EXISTS public.routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fleet_id UUID NOT NULL,
    name VARCHAR(100) NOT NULL, -- Ej: 'SECTOR A ➔ RAMPA SUR'
    origin_zone VARCHAR(50) NOT NULL,
    destination_zone VARCHAR(50) NOT NULL,
    est_duration_minutes INT DEFAULT 15,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Inyectar capacidad volumétrica en la tabla de activos (Si no existía)
ALTER TABLE public.assets ADD COLUMN IF NOT EXISTS hopper_capacity_m3 NUMERIC(5,2) DEFAULT 18.00;

-- 3. TABLA TRANSACCIONAL DE CICLOS DE ACARREO (MAQUINA DE ESTADOS)
CREATE TABLE IF NOT EXISTS public.haul_cycles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fleet_id UUID NOT NULL,
    asset_id UUID NOT NULL REFERENCES public.assets(id),
    operator_uid UUID NOT NULL REFERENCES auth.users(id),
    shift_id UUID NOT NULL REFERENCES public.shift_logs(id), -- ENCLAVAMIENTO CON CONDUCTO 1
    route_id UUID REFERENCES public.routes(id),
    material_id UUID REFERENCES public.materials(id),
    state VARCHAR(20) NOT NULL CHECK (state IN ('LOADING', 'HAULING', 'DUMPING', 'RETURNING', 'COMPLETED', 'ABORTED')),
    tonnage_moved NUMERIC(8,2) DEFAULT 0.00,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    loaded_at TIMESTAMPTZ DEFAULT NULL,
    dumped_at TIMESTAMPTZ DEFAULT NULL,
    completed_at TIMESTAMPTZ DEFAULT NULL,
    cycle_duration_seconds INT DEFAULT 0
);

-- Índice parcial para prevenir múltiples ciclos activos sobre el mismo camión o conductor
CREATE UNIQUE INDEX IF NOT EXISTS idx_active_asset_haul_cycle 
ON public.haul_cycles(asset_id) 
WHERE state NOT IN ('COMPLETED', 'ABORTED');

-- Escudo WORM: Nadie puede alterar el tonelaje o tiempos de los ciclos cerrados
REVOKE DELETE, UPDATE ON public.haul_cycles FROM authenticated, anon;

-- 4. PROCEDIMIENTO ATÓMICO DE TRANSICIÓN DE DESPACHO
CREATE OR REPLACE FUNCTION public.fn_execute_haul_transition(
    p_asset_id UUID,
    p_action VARCHAR(20), -- 'START_LOADING', 'FINISH_LOADING', 'CONFIRM_DUMP', 'COMPLETE_CYCLE', 'ABORT'
    p_route_id UUID DEFAULT NULL,
    p_material_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_uid UUID;
    v_shift RECORD;
    v_cycle RECORD;
    v_asset RECORD;
    v_material RECORD;
    v_calc_tonnage NUMERIC(8,2) := 0.00;
    v_now TIMESTAMPTZ := now();
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Terminal carece de sesión AAL2 válida.' USING ERRCODE = '40100';
    END IF;

    -- =========================================================================
    -- ADUANA 1: ENCLAVAMIENTO CON EL RELOJ DE FATIGA (CONDUCTO 1)
    -- =========================================================================
    SELECT id, fleet_id, status INTO v_shift 
    FROM public.shift_logs 
    WHERE operator_uid = v_caller_uid AND status = 'ACTIVE'
    ORDER BY started_at DESC LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'WHS_INTERLOCK: Prohibido iniciar o mutar ciclos de acarreo sin una jornada laboral ACTIVA en el reloj de fatiga.' 
            USING ERRCODE = '42501';
    END IF;

    -- Verificar que la maquinaria esté asignada y operativa
    SELECT id, fleet_id, status, hopper_capacity_m3 INTO v_asset 
    FROM public.assets WHERE id = p_asset_id FOR UPDATE;

    IF NOT FOUND OR v_asset.fleet_id != v_shift.fleet_id THEN
        RAISE EXCEPTION 'ASSET_VIOLATION: Maquinaria inexistente o fuera de su jurisdicción.' USING ERRCODE = '42501';
    END IF;

    IF v_asset.status = 'OUT_OF_SERVICE' THEN
        RAISE EXCEPTION 'WHS_LOCKOUT: La maquinaria se encuentra INHABILITADA por seguridad. Prohibido cargar material.' USING ERRCODE = '42501';
    END IF;

    -- Consultar si ya existe un ciclo activo para este camión
    SELECT * INTO v_cycle FROM public.haul_cycles 
    WHERE asset_id = p_asset_id AND state NOT IN ('COMPLETED', 'ABORTED')
    FOR UPDATE;

    -- =========================================================================
    -- MÁQUINA DE ESTADOS INDUSTRIAL: TRANSICIONES INMUTABLES
    -- =========================================================================
    IF p_action = 'START_LOADING' THEN
        IF FOUND THEN
            RAISE EXCEPTION 'CYCLE_IN_PROGRESS: El camión ya se encuentra en estado %. Cierre el ciclo actual antes de iniciar una nueva carga.', v_cycle.state
                USING ERRCODE = '40900';
        END IF;

        IF p_route_id IS NULL OR p_material_id IS NULL THEN
            RAISE EXCEPTION 'PARAM_REQUIRED: Debe indicar ruta y tipo de material para posicionarse en excavadora.' USING ERRCODE = '22023';
        END IF;

        INSERT INTO public.haul_cycles (fleet_id, asset_id, operator_uid, shift_id, route_id, material_id, state, started_at)
        VALUES (v_shift.fleet_id, p_asset_id, v_caller_uid, v_shift.id, p_route_id, p_material_id, 'LOADING', v_now)
        RETURNING * INTO v_cycle;

        UPDATE public.assets SET status = 'DISPATCHED', updated_at = v_now WHERE id = p_asset_id;

        RETURN jsonb_build_object('success', true, 'state', 'LOADING', 'cycle_id', v_cycle.id, 'started_at', v_now);

    ELSIF p_action = 'FINISH_LOADING' THEN
        IF NOT FOUND OR v_cycle.state != 'LOADING' THEN
            RAISE EXCEPTION 'TRANSITION_ERROR: No puede iniciar tránsito sin haber estado en carga (LOADING).' USING ERRCODE = '40000';
        END IF;

        -- CÁLCULO MATEMÁTICO DE TONELAJE (Volumen Tolva x Densidad Material)
        SELECT density_kg_m3 INTO v_material FROM public.materials WHERE id = v_cycle.material_id;
        IF FOUND THEN
            v_calc_tonnage := (COALESCE(v_asset.hopper_capacity_m3, 18.00) * v_material.density_kg_m3) / 1000.0;
        END IF;

        UPDATE public.haul_cycles 
        SET state = 'HAULING', loaded_at = v_now, tonnage_moved = v_calc_tonnage 
        WHERE id = v_cycle.id;

        RETURN jsonb_build_object('success', true, 'state', 'HAULING', 'tonnage_moved', v_calc_tonnage);

    ELSIF p_action = 'CONFIRM_DUMP' THEN
        IF NOT FOUND OR v_cycle.state != 'HAULING' THEN
            RAISE EXCEPTION 'TRANSITION_ERROR: Prohibido descargar sin haber completado la carga y el tránsito.' USING ERRCODE = '40000';
        END IF;

        UPDATE public.haul_cycles SET state = 'RETURNING', dumped_at = v_now WHERE id = v_cycle.id;

        RETURN jsonb_build_object('success', true, 'state', 'RETURNING', 'dumped_at', v_now);

    ELSIF p_action = 'COMPLETE_CYCLE' THEN
        IF NOT FOUND OR v_cycle.state != 'RETURNING' THEN
            RAISE EXCEPTION 'TRANSITION_ERROR: No puede cerrar ciclo sin haber vaciado la tolva en destino.' USING ERRCODE = '40000';
        END IF;

        UPDATE public.haul_cycles 
        SET state = 'COMPLETED', completed_at = v_now,
            cycle_duration_seconds = EXTRACT(EPOCH FROM (v_now - v_cycle.started_at))::INT
        WHERE id = v_cycle.id;

        -- Devolver camión a estado disponible para el siguiente ciclo
        UPDATE public.assets SET status = 'AVAILABLE', updated_at = v_now WHERE id = p_asset_id;

        RETURN jsonb_build_object(
            'success', true, 'state', 'COMPLETED', 
            'tonnage_added', v_cycle.tonnage_moved,
            'duration_seconds', EXTRACT(EPOCH FROM (v_now - v_cycle.started_at))::INT
        );

    ELSIF p_action = 'ABORT' THEN
        IF NOT FOUND THEN RETURN jsonb_build_object('success', true, 'state', 'ABORTED'); END IF;
        
        UPDATE public.haul_cycles SET state = 'ABORTED', completed_at = v_now WHERE id = v_cycle.id;
        UPDATE public.assets SET status = 'AVAILABLE', updated_at = v_now WHERE id = p_asset_id;
        
        RETURN jsonb_build_object('success', true, 'state', 'ABORTED', 'msg', 'Ciclo cancelado.');
    END IF;

    RAISE EXCEPTION 'UNKNOWN_ACTION: La directiva % no es reconocida por el motor de despacho.', p_action USING ERRCODE = '22023';
END;
$$;
