-- 1. Ampliación del Perfil con Lógica de Seguros y Auditoría
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS insurance_policy_number VARCHAR(100),
ADD COLUMN IF NOT EXISTS insurance_expiry_date DATE;

-- FIX ARQUITECTÓNICO: PostgreSQL no permite CURRENT_DATE en columnas GENERATED ALWAYS.
-- Se implementa como Columna Computada de Supabase (PostgREST) para mantener la misma API.
CREATE OR REPLACE FUNCTION insurance_compliant(profiles)
RETURNS BOOLEAN AS $$
  SELECT $1.insurance_expiry_date > CURRENT_DATE;
$$ LANGUAGE sql STABLE;

-- 2. Almacén de Documentos Verificables (Lo que pide el Inspector)
CREATE TABLE IF NOT EXISTS compliance_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  doc_type VARCHAR(50) NOT NULL, -- 'INSURANCE', 'VEHICLE_REG', 'DRIVER_LICENSE'
  file_url VARCHAR(2048) NOT NULL,
  expiry_date DATE NOT NULL,
  is_verified BOOLEAN DEFAULT false,
  verified_by UUID, -- ID del Admin que dio el visto bueno
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Tabla de Auditoría de Acceso (Trazabilidad Forense)
CREATE TABLE IF NOT EXISTS access_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES profiles(id),
  table_name VARCHAR(100) NOT NULL,
  row_id UUID NOT NULL,
  action VARCHAR(20) NOT NULL, -- 'SELECT', 'INSERT', 'UPDATE'
  timestamp TIMESTAMPTZ DEFAULT now()
);

-- 4. Bloqueo de Seguridad en el nivel de Motor (Trigger de Validación)
CREATE OR REPLACE FUNCTION check_insurance_compliance()
RETURNS TRIGGER AS $$
BEGIN
  -- Reemplazamos la columna estática por la evaluación en tiempo real
  IF NOT (SELECT insurance_expiry_date > CURRENT_DATE FROM profiles WHERE id = NEW.contractor_id) THEN
    RAISE EXCEPTION 'El contratista no cumple con los requisitos de seguro vigentes.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_block_uninsured_contractor ON load_offers;
CREATE TRIGGER trigger_block_uninsured_contractor
BEFORE INSERT ON load_offers
FOR EACH ROW EXECUTE FUNCTION check_insurance_compliance();
