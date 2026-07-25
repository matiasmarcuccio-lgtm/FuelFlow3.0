-- 1. Definición de Modelos de Alquiler
CREATE TYPE public.hire_model_type AS ENUM ('dry_hire', 'wet_hire');

-- 2. La Bóveda de Contratos
CREATE TABLE public.billing_contracts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID NOT NULL REFERENCES public.assets(id) ON DELETE CASCADE,
    model hire_model_type NOT NULL,
    
    -- Tarifas base por hora
    hourly_rate_asset NUMERIC(10, 2) NOT NULL,
    hourly_rate_operator NUMERIC(10, 2) DEFAULT 0.00,
    
    -- Multiplicadores de fatiga (Horas extra tras umbral legal)
    overtime_multiplier NUMERIC(4, 2) DEFAULT 1.50,
    overtime_threshold_hours NUMERIC(4, 2) DEFAULT 8.00,
    
    currency VARCHAR(3) DEFAULT 'AUD',
    is_active BOOLEAN DEFAULT true,
    updated_at TIMESTAMPTZ DEFAULT now(),
    
    CONSTRAINT uq_active_contract UNIQUE (asset_id)
);

-- 3. Aislamiento RLS
ALTER TABLE public.billing_contracts ENABLE ROW LEVEL SECURITY;
-- (Asumimos políticas donde solo 'fleet_manager' o 'super_admin' pueden mutar contratos)

-- 4. Certificados de Ejecución Inmutables
CREATE TABLE public.execution_certificates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES public.asset_assignments(id) ON DELETE CASCADE,
    contract_id UUID NOT NULL REFERENCES public.billing_contracts(id),
    
    -- Telemetría de Tiempo (Horas decimales)
    total_hours NUMERIC(8, 2) NOT NULL,
    regular_hours NUMERIC(8, 2) NOT NULL,
    overtime_hours NUMERIC(8, 2) NOT NULL,
    
    -- Cuantificación Financiera
    asset_subtotal NUMERIC(12, 2) NOT NULL,
    operator_subtotal NUMERIC(12, 2) NOT NULL,
    total_billable NUMERIC(12, 2) NOT NULL,
    
    -- Metadatos de Auditoría
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sync_status VARCHAR(50) DEFAULT 'pending_erp_export',
    
    CONSTRAINT uq_assignment_certificate UNIQUE (assignment_id)
);

ALTER TABLE public.execution_certificates ENABLE ROW LEVEL SECURITY;

-- 5. RPC de Cuantificación Matemática
CREATE OR REPLACE FUNCTION public.generate_execution_certificate()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_contract RECORD;
    v_total_hours NUMERIC(8, 2);
    v_regular_hours NUMERIC(8, 2);
    v_overtime_hours NUMERIC(8, 2);
    v_asset_subtotal NUMERIC(12, 2);
    v_operator_subtotal NUMERIC(12, 2);
    v_total NUMERIC(12, 2);
BEGIN
    -- Solo actuar cuando un turno se cierra legalmente
    IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        
        -- Buscar el contrato activo del activo operado
        SELECT * INTO v_contract 
        FROM public.billing_contracts 
        WHERE asset_id = NEW.asset_id AND is_active = true;
        
        -- Si no hay contrato, no se genera cobro, pero no bloqueamos la operación
        IF NOT FOUND THEN
            RETURN NEW;
        END IF;

        -- Calcular horas decimales exactas desde el inicio del Pre-Start hasta el fin del turno
        -- (En un escenario más complejo, restarías el tiempo de pausas documentadas)
        v_total_hours := ROUND((EXTRACT(EPOCH FROM (NEW.shift_end - NEW.prestart_commenced_at)) / 3600.0)::numeric, 2);
        
        -- Prevenir horas negativas por posibles anomalías de datos
        IF v_total_hours < 0 THEN v_total_hours := 0; END IF;

        -- Calcular desglose de Horas Extra (WHS Overtime)
        IF v_total_hours > v_contract.overtime_threshold_hours THEN
            v_regular_hours := v_contract.overtime_threshold_hours;
            v_overtime_hours := v_total_hours - v_contract.overtime_threshold_hours;
        ELSE
            v_regular_hours := v_total_hours;
            v_overtime_hours := 0;
        END IF;

        -- Cuantificación Asset (Dry Hire base)
        v_asset_subtotal := v_total_hours * v_contract.hourly_rate_asset;

        -- Cuantificación Operator (Wet Hire)
        IF v_contract.model = 'wet_hire' THEN
            v_operator_subtotal := (v_regular_hours * v_contract.hourly_rate_operator) +
                                   (v_overtime_hours * (v_contract.hourly_rate_operator * v_contract.overtime_multiplier));
        ELSE
            v_operator_subtotal := 0;
        END IF;

        v_total := v_asset_subtotal + v_operator_subtotal;

        -- Inyección en el Libro Mayor
        INSERT INTO public.execution_certificates (
            assignment_id, contract_id, total_hours, regular_hours, overtime_hours,
            asset_subtotal, operator_subtotal, total_billable
        ) VALUES (
            NEW.id, v_contract.id, v_total_hours, v_regular_hours, v_overtime_hours,
            v_asset_subtotal, v_operator_subtotal, v_total
        );
        
    END IF;
    
    RETURN NEW;
END;
$$;

-- 6. El Disparador
DROP TRIGGER IF EXISTS trg_close_shift_billing ON public.asset_assignments;
CREATE TRIGGER trg_close_shift_billing
AFTER UPDATE OF status ON public.asset_assignments
FOR EACH ROW
EXECUTE FUNCTION public.generate_execution_certificate();
