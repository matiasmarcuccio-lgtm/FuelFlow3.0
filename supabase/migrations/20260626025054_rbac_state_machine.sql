-- FASE 1: DEFINICIÓN DE ROLES Y ASIGNACIONES
-- Definición de roles (usaremos el tipo nativo de Postgres)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('contractor', 'operator', 'admin');
    END IF;
END$$;

-- Tabla de Asignaciones: Define quién tiene el derecho exclusivo sobre una oferta
CREATE TABLE IF NOT EXISTS assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  load_offer_id UUID REFERENCES load_offers(id) ON DELETE CASCADE,
  operator_id UUID NOT NULL, -- Referencia al perfil del transportista
  assigned_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT unique_assignment UNIQUE (load_offer_id) -- Solo un operador por oferta
);

-- FASE 2: MÁQUINA DE ESTADOS (STATE LOCK)
-- Modificar la tabla load_offers para soportar los estados estrictos
ALTER TABLE load_offers DROP COLUMN IF EXISTS status;
ALTER TABLE load_offers 
ADD COLUMN status VARCHAR(20) DEFAULT 'BIDDING_OPEN' 
CHECK (status IN ('BIDDING_OPEN', 'BIDDING_LOCKED', 'MANIFEST_PENDING', 'COMPLETED', 'AUDITED'));

-- Función de bloqueo de integridad
CREATE OR REPLACE FUNCTION protect_contract_lifecycle()
RETURNS TRIGGER AS $$
BEGIN
  -- Si el estado ya no es abierto, prohibir modificar elementos estructurales
  IF (SELECT status FROM load_offers WHERE id = NEW.load_offer_id) != 'BIDDING_OPEN' THEN
    RAISE EXCEPTION 'El contrato está bloqueado. No se pueden modificar elementos estructurales una vez iniciada la puja.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Aplicar el trigger a la tabla de elementos estructurales
DROP TRIGGER IF EXISTS trigger_lock_structural_elements ON structural_elements;
CREATE TRIGGER trigger_lock_structural_elements
BEFORE UPDATE OR DELETE ON structural_elements
FOR EACH ROW EXECUTE FUNCTION protect_contract_lifecycle();

-- FASE 3: POLÍTICAS DE SEGURIDAD (RLS)
-- Habilitar RLS en tablas críticas
ALTER TABLE load_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE cor_manifests ENABLE ROW LEVEL SECURITY;

-- Política: El operador solo ve lo que tiene asignado
DROP POLICY IF EXISTS operator_view_policy ON load_offers;
CREATE POLICY operator_view_policy ON load_offers
FOR SELECT
USING (id IN (SELECT load_offer_id FROM assignments WHERE operator_id = auth.uid()));

-- Política: Solo el dueño de la asignación puede insertar el manifiesto CoR
DROP POLICY IF EXISTS operator_insert_manifest ON cor_manifests;
CREATE POLICY operator_insert_manifest ON cor_manifests
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM assignments 
    WHERE load_offer_id = cor_manifests.load_offer_id 
    AND operator_id = auth.uid()
  )
);
