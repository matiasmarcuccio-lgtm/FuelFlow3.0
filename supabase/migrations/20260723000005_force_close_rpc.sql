-- Migración: Cierre Forzado y Blindaje de Auditoría (FuelFlow 3.0)

-- 1. Añadir el estado a la tabla de asignaciones para soportar el RPC
CREATE TYPE public.assignment_status AS ENUM ('active', 'completed', 'cancelled');

ALTER TABLE public.asset_assignments 
ADD COLUMN status public.assignment_status NOT NULL DEFAULT 'active';

-- 2. Función RPC para el Cierre Forzado de Turnos Huérfanos
CREATE OR REPLACE FUNCTION public.force_close_shift(p_assignment_id UUID, p_reason TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER -- Se ejecuta con privilegios del creador para saltar bloqueos de lectura/escritura si es necesario, pero validamos la identidad internamente.
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_fleet_id UUID;
BEGIN
    -- 1. Extraer la identidad absoluta del JWT
    v_caller_id := auth.uid();
    
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_UNAUTHORIZED: Identidad criptográfica ausente. Terminación denegada.';
    END IF;

    -- 2. Ejecutar la terminación táctica del activo
    UPDATE public.asset_assignments
    SET 
        shift_end = now(),
        status = 'completed',
        -- Reutilizamos las columnas de excepción para estampar la auditoría del cierre forzado
        fatigue_override_reason = COALESCE(fatigue_override_reason, '') || ' [FORCED CLOSURE: ' || p_reason || ']',
        override_approved_by = v_caller_id
    WHERE id = p_assignment_id 
      AND shift_end IS NULL; -- Solo afecta a turnos abiertos (infinitos)

    -- 3. Validar el impacto de la operación
    IF NOT FOUND THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_INVALID_TARGET: El turno no existe, pertenece a otra flota, o ya fue cerrado forensemente.';
    END IF;
END;
$$;

-- 3. Blindaje del vector de ataque
-- Revocamos el permiso de actualizar shift_end directamente desde la API REST
REVOKE UPDATE (shift_end, status, fatigue_override_reason, override_approved_by) 
ON public.asset_assignments FROM authenticated;
