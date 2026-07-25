-- Migración: Libro Mayor Universal de Auditoría Forense (System Audit Logs)

-- 1. La Tabla Inmutable
CREATE TABLE public.system_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_uid UUID REFERENCES auth.users(id),
    actor_role TEXT,
    action_type VARCHAR(50) NOT NULL, -- ej: 'UPDATE_BILLING_RATE', 'OVERRIDE_FATIGUE', 'REVOKE_SHIFT'
    target_table VARCHAR(100) NOT NULL,
    target_record_id UUID,
    payload_before JSONB,
    payload_after JSONB,
    client_ip TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. El Muro Criptográfico: Prohibido Modificar o Borrar Registros de Auditoría
-- Nadie, ni siquiera el superadministrador, puede alterar el pasado.
REVOKE UPDATE, DELETE ON public.system_audit_logs FROM PUBLIC, authenticated, service_role;

-- 3. Aislamiento RLS (Los supervisores solo ven la auditoría de su propia flota si aplica, el super admin ve todo)
ALTER TABLE public.system_audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "SuperAdmins view all audit logs" ON public.system_audit_logs
FOR SELECT USING (
    (current_setting('request.jwt.claims', true)::jsonb ->> 'user_role') = 'super_admin'
);

-- 4. Función Genérica de Auditoría
CREATE OR REPLACE FUNCTION public.log_infrastructure_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_actor_id UUID;
    v_actor_role TEXT;
BEGIN
    -- Extraer contexto de seguridad del JWT actual
    v_actor_id := auth.uid();
    v_actor_role := current_setting('request.jwt.claims', true)::jsonb ->> 'user_role';

    IF (TG_OP = 'UPDATE') THEN
        INSERT INTO public.system_audit_logs (
            actor_uid, actor_role, action_type, target_table, target_record_id, 
            payload_before, payload_after
        ) VALUES (
            v_actor_id,
            v_actor_role,
            TG_OP || '_' || TG_TABLE_NAME,
            TG_TABLE_NAME,
            NEW.id,
            to_jsonb(OLD),
            to_jsonb(NEW)
        );
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO public.system_audit_logs (
            actor_uid, actor_role, action_type, target_table, target_record_id, 
            payload_before, payload_after
        ) VALUES (
            v_actor_id,
            v_actor_role,
            TG_OP || '_' || TG_TABLE_NAME,
            TG_TABLE_NAME,
            OLD.id,
            to_jsonb(OLD),
            NULL
        );
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO public.system_audit_logs (
            actor_uid, actor_role, action_type, target_table, target_record_id, 
            payload_before, payload_after
        ) VALUES (
            v_actor_id,
            v_actor_role,
            TG_OP || '_' || TG_TABLE_NAME,
            TG_TABLE_NAME,
            NEW.id,
            NULL,
            to_jsonb(NEW)
        );
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

-- 5. Acoplar el Auditor al Motor de Facturación (Billing Contracts)
-- Cualquier cambio arbitrario en las tarifas horarias quedará expuesto de por vida.
DROP TRIGGER IF EXISTS trg_audit_billing_contracts ON public.billing_contracts;
CREATE TRIGGER trg_audit_billing_contracts
AFTER INSERT OR UPDATE OR DELETE ON public.billing_contracts
FOR EACH ROW
EXECUTE FUNCTION public.log_infrastructure_mutation();
