CREATE EXTENSION IF NOT EXISTS pg_net;

-- 1. Trigger para el Matchmaking JIT al crear una Oferta
CREATE OR REPLACE FUNCTION trigger_matchmaking_after_load_offer()
RETURNS TRIGGER AS $$
BEGIN
  -- Invocación asíncrona de la Edge Function mediante pg_net
  -- Nota: Actualizar URL en producción o usar Vault para el dominio base
  PERFORM net.http_post(
    url := 'https://tu-proyecto.supabase.co/functions/v1/matchmaking-engine',
    body := jsonb_build_object('load_offer_id', NEW.id)
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_after_load_offer_insert ON load_offers;
CREATE TRIGGER trg_after_load_offer_insert
AFTER INSERT ON load_offers
FOR EACH ROW EXECUTE FUNCTION trigger_matchmaking_after_load_offer();

-- 2. Trigger para Auditoría al subir documento de cumplimiento
CREATE OR REPLACE FUNCTION trigger_audit_compliance_doc()
RETURNS TRIGGER AS $$
BEGIN
  -- Registro automático en el historial forense
  INSERT INTO access_logs (user_id, table_name, row_id, action)
  VALUES (auth.uid(), 'compliance_documents', NEW.id, 'INSERT');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER; -- Se añade SECURITY DEFINER para saltar RLS de inserción

DROP TRIGGER IF EXISTS trg_after_compliance_doc_upload ON compliance_documents;
CREATE TRIGGER trg_after_compliance_doc_upload
AFTER INSERT ON compliance_documents
FOR EACH ROW EXECUTE FUNCTION trigger_audit_compliance_doc();
