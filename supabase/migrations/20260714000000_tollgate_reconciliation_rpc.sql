-- 20260714000000_tollgate_reconciliation_rpc.sql
-- RPC Transaccional Atómico para el Cierre Forense en Báscula (Tollgate UI)

SET search_path = public, postgis;

-- 1. Añadir columna criptográfica/forense
-- Referencia directamente a auth.users para evitar manipulaciones en perfiles públicos
ALTER TABLE load_cycles 
ADD COLUMN IF NOT EXISTS reconciled_by UUID REFERENCES auth.users(id);

-- 2. El RPC Atómico Inquebrantable
CREATE OR REPLACE FUNCTION reconcile_load_cycle(
    p_cycle_id UUID,
    p_gross_weight NUMERIC,
    p_tare_weight NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER -- Ejecuta con permisos elevados para garantizar el UPDATE
AS $$
DECLARE
    v_cycle_record RECORD;
    v_operator_id UUID;
BEGIN
    -- Capturar la identidad del usuario que ejecuta la función
    v_operator_id := auth.uid();
    
    IF v_operator_id IS NULL THEN
        RAISE EXCEPTION 'Aduana: Se requiere autenticación criptográfica para facturar.';
    END IF;

    -- Bloqueo transaccional FOR UPDATE: 
    -- Evita que dos clics simultáneos procesen el mismo ciclo (Double-Spending)
    SELECT * INTO v_cycle_record 
    FROM load_cycles 
    WHERE id = p_cycle_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Aduana: El ticket de carga % no existe.', p_cycle_id;
    END IF;

    -- Validación estricta de la Máquina de Estados
    IF v_cycle_record.status != 'in_transit' THEN
        RAISE EXCEPTION 'Aduana: Rechazado. El ciclo está en estado % (Debe ser in_transit).', v_cycle_record.status;
    END IF;

    IF p_gross_weight <= p_tare_weight THEN
        RAISE EXCEPTION 'Aduana: Rechazado. El peso bruto debe ser mayor al peso tara.';
    END IF;

    -- Ejecutar el cierre financiero. 
    -- Nota: net_weight se autocalcula en la tabla (generated always as gross - tare)
    UPDATE load_cycles
    SET 
        status = 'reconciled',
        gross_weight = p_gross_weight,
        tare_weight = p_tare_weight,
        completed_at = CURRENT_TIMESTAMP,
        reconciled_by = v_operator_id
    WHERE id = p_cycle_id;

    -- Retornar el payload serializado para el Kiosk
    RETURN jsonb_build_object(
        'success', true,
        'cycle_id', p_cycle_id,
        'status', 'reconciled',
        'message', 'Ticket cerrado y conciliado exitosamente'
    );
END;
$$;
