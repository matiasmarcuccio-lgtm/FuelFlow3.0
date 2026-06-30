-- Habilitar extensiones necesarias para PostGIS y earthdistance si no existen
CREATE EXTENSION IF NOT EXISTS cube;
CREATE EXTENSION IF NOT EXISTS earthdistance;

-- 1. ESTRUCTURA DE FLOTA (Extensión)
ALTER TABLE assets
ADD COLUMN IF NOT EXISTS has_4x4_traction BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS turning_radius_m DECIMAL(4,2),
ADD COLUMN IF NOT EXISTS max_load_length_mm INTEGER,
ADD COLUMN IF NOT EXISTS max_load_width_mm INTEGER;

-- 2. ORQUESTADOR JIT (Load Board de Obra Civil)
CREATE TABLE load_offers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  contractor_id UUID NOT NULL,
  crane_window_start TIMESTAMPTZ NOT NULL,
  crane_window_end TIMESTAMPTZ NOT NULL,
  destination_lat DECIMAL(10, 8) NOT NULL,
  destination_lng DECIMAL(11, 8) NOT NULL,
  requires_4x4_traction BOOLEAN DEFAULT false,
  max_turn_radius_m DECIMAL(4,2),
  status VARCHAR(50) DEFAULT 'BIDDING_OPEN',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. GEMELO DIGITAL (Trazabilidad BIM)
CREATE TABLE structural_elements (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  load_offer_id UUID REFERENCES load_offers(id) ON DELETE CASCADE,
  bim_guid VARCHAR(255) NOT NULL,
  element_type VARCHAR(100) NOT NULL,
  length_mm INTEGER NOT NULL,
  width_mm INTEGER NOT NULL,
  weight_kg DECIMAL(8,2) NOT NULL
);

-- 4. LIBRO MAYOR CoR (Inmutable)
CREATE TABLE cor_manifests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  load_offer_id UUID REFERENCES load_offers(id),
  operator_id UUID NOT NULL,
  action VARCHAR(50) NOT NULL,
  loader_signature_hash VARCHAR(64) NOT NULL,
  driver_signature_hash VARCHAR(64) NOT NULL,
  gps_location POINT NOT NULL,
  server_timestamp TIMESTAMPTZ DEFAULT now()
);

-- 5. EVIDENCIA DE FATIGA (Escudo de Debida Diligencia)
CREATE TABLE driver_fatigue_evidence (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  load_offer_id UUID REFERENCES load_offers(id) ON DELETE CASCADE,
  operator_id UUID NOT NULL,
  evidence_url VARCHAR(2048) NOT NULL,
  evidence_hash VARCHAR(64) NOT NULL,
  upload_timestamp TIMESTAMPTZ DEFAULT now(),
  gps_location POINT NOT NULL,
  status VARCHAR(20) DEFAULT 'PENDING',
  reviewer_id UUID,
  rejection_reason TEXT
);

-- 6. INDICES PARA EL MOTOR DE MATCHMAKING (Optimización PostGIS)
CREATE INDEX idx_load_offers_location ON load_offers USING GIST (ll_to_earth(destination_lat, destination_lng));
CREATE INDEX idx_structural_elements_guid ON structural_elements(bim_guid);
