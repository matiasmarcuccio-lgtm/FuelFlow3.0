ALTER TABLE public.assets
ADD COLUMN IF NOT EXISTS is_nhvr_accredited BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS trailer_type VARCHAR(50),
ADD COLUMN IF NOT EXISTS max_payload_kg DECIMAL(10,2),
ADD COLUMN IF NOT EXISTS pallet_capacity INTEGER,
ADD COLUMN IF NOT EXISTS vehicle_metadata JSONB DEFAULT '{}'::jsonb,
ADD COLUMN IF NOT EXISTS compliance_records JSONB DEFAULT '{}'::jsonb,
ADD COLUMN IF NOT EXISTS special_features JSONB DEFAULT '[]'::jsonb;
