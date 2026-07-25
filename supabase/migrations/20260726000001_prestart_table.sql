-- Migración: Pre-Start Compliance (Fricción Temporal y Bifurcación) PARTE 2

-- 1. Alterar el default ahora que el enum ya fue registrado en la transacción anterior
ALTER TABLE public.asset_assignments ALTER COLUMN status SET DEFAULT 'pending_prestart';

-- 2. La Tabla de Inspección de Seguridad
CREATE TABLE public.prestart_checks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES public.asset_assignments(id) ON DELETE CASCADE,
    operator_id UUID NOT NULL REFERENCES auth.users(id),
    
    -- Inspecciones Críticas (Booleanos)
    brakes_checked BOOLEAN NOT NULL DEFAULT false,
    fluids_checked BOOLEAN NOT NULL DEFAULT false,
    structural_checked BOOLEAN NOT NULL DEFAULT false,
    
    -- Veredicto de Operatividad
    is_safe_to_operate BOOLEAN NOT NULL,
    defect_notes TEXT,
    
    -- Biometría Temporal (Anti Pencil-Whipping)
    inspection_started_at TIMESTAMPTZ NOT NULL,
    inspection_completed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- LA LEY INQUEBRANTABLE: Obliga a una diferencia de tiempo (Ej: 60 segundos mínimo)
    CONSTRAINT prestart_time_friction CHECK (
        EXTRACT(EPOCH FROM (inspection_completed_at - inspection_started_at)) >= 60
    )
);

-- 3. Aislamiento RLS
ALTER TABLE public.prestart_checks ENABLE ROW LEVEL SECURITY;

-- Ningún supervisor puede modificar una inspección. Solo lectura.
CREATE POLICY "Supervisors can view prestarts" ON public.prestart_checks
FOR SELECT USING (
    (current_setting('request.jwt.claims', true)::jsonb ->> 'user_role') IN ('supervisor', 'fleet_manager', 'super_admin')
); 

-- 4. RPC de Certificación Matemática
CREATE OR REPLACE FUNCTION public.certify_prestart(
    p_assignment_id UUID,
    p_started_at TIMESTAMPTZ,
    p_brakes BOOLEAN,
    p_fluids BOOLEAN,
    p_structural BOOLEAN,
    p_is_safe BOOLEAN,
    p_defect_notes TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_role TEXT;
    v_assignment_record RECORD;
BEGIN
    v_caller_id := auth.uid();
    -- Obtenemos el rol desde profiles ya que es donde está configurado realmente.
    SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id;

    -- 1. Bloqueo transaccional del turno
    SELECT * INTO v_assignment_record 
    FROM public.asset_assignments 
    WHERE id = p_assignment_id FOR UPDATE;

    -- Validar jurisdicción
    IF v_assignment_record.driver_id != v_caller_id THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_UNAUTHORIZED: Solo el operador asignado al activo puede firmar legalmente el pre-start.';
    END IF;

    -- Validar estado logístico (Asumiendo que el despacho ahora nace como 'pending_prestart')
    IF v_assignment_record.status != 'pending_prestart' THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_CONFLICT: El turno ya fue iniciado o cerrado.';
    END IF;

    -- 2. Inserción de la Certificación (Aquí PostgreSQL evalúa prestart_time_friction)
    INSERT INTO public.prestart_checks (
        assignment_id, operator_id, brakes_checked, fluids_checked, structural_checked, 
        is_safe_to_operate, defect_notes, inspection_started_at, inspection_completed_at
    ) VALUES (
        p_assignment_id, v_caller_id, p_brakes, p_fluids, p_structural, 
        p_is_safe, p_defect_notes, p_started_at, now()
    );

    -- 3. Bifurcación Física del Activo
    IF p_is_safe THEN
        -- El operador certificó la máquina. El reloj comienza a correr.
        UPDATE public.asset_assignments 
        SET status = 'in_progress' 
        WHERE id = p_assignment_id;
    ELSE
        -- El operador detectó una falla crítica.
        -- 1. Cortar el turno inmediatamente (Shift_End = now)
        UPDATE public.asset_assignments 
        SET status = 'completed', shift_end = now() 
        WHERE id = p_assignment_id;
        
        -- 2. Secuestrar la máquina a favor del taller.
        -- Esto rompe el ciclo logístico y fuerza la intervención del Módulo de Taller.
        UPDATE public.assets 
        SET status = 'maintenance' 
        WHERE id = v_assignment_record.asset_id;
        
        -- Inyectar automáticamente en maintenance_logs para disparar el Webhook de forma nativa
        INSERT INTO public.maintenance_logs (asset_id, locked_by_uid, issue_description)
        VALUES (v_assignment_record.asset_id, v_caller_id, 'PRE-START FAILURE: ' || COALESCE(p_defect_notes, 'Unspecified hazard'));
    END IF;
END;
$$;

-- 5. Revocar actualización de estado desde REST para el operador
REVOKE UPDATE (status) ON public.asset_assignments FROM authenticated;
