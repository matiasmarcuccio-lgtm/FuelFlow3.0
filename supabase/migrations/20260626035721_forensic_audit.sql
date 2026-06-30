-- FASE 1: TRIGGER FORENSE AUTOMÁTICO
CREATE OR REPLACE FUNCTION audit_log_changes()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO access_logs (user_id, table_name, row_id, action)
  VALUES (auth.uid(), TG_TABLE_NAME, COALESCE(NEW.id, OLD.id), TG_OP);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Aplicar a tablas sensibles
DROP TRIGGER IF EXISTS audit_load_offers ON load_offers;
CREATE TRIGGER audit_load_offers AFTER INSERT OR UPDATE OR DELETE ON load_offers FOR EACH ROW EXECUTE FUNCTION audit_log_changes();

DROP TRIGGER IF EXISTS audit_cor_manifests ON cor_manifests;
CREATE TRIGGER audit_cor_manifests AFTER INSERT OR UPDATE OR DELETE ON cor_manifests FOR EACH ROW EXECUTE FUNCTION audit_log_changes();

-- FASE 2: REFINE DE BLOQUEO (PUERTA DE RESCATE)
CREATE OR REPLACE FUNCTION check_insurance_compliance()
RETURNS TRIGGER AS $$
BEGIN
  -- Se evalúa la fecha directamente debido a que 'insurance_compliant' es una función computada
  IF (SELECT insurance_expiry_date > CURRENT_DATE FROM profiles WHERE id = NEW.contractor_id) OR 
     (TG_TABLE_NAME = 'compliance_documents') THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Operación bloqueada: Póliza expirada. Suba su documentación en la sección de cumplimiento.';
END;
$$ LANGUAGE plpgsql;

-- FASE 3: POLÍTICAS RLS FINALES (BLINDAJE TOTAL)
ALTER TABLE public.compliance_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.access_logs ENABLE ROW LEVEL SECURITY;

-- Política: Solo ver tus propios documentos
DROP POLICY IF EXISTS view_own_docs ON public.compliance_documents;
CREATE POLICY view_own_docs ON public.compliance_documents
FOR ALL USING (profile_id = auth.uid());

-- Política: Solo el Admin puede ver logs (Asumiendo que el Admin tiene un rol especial)
DROP POLICY IF EXISTS admin_view_logs ON public.access_logs;
CREATE POLICY admin_view_logs ON public.access_logs
FOR SELECT USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
); 
