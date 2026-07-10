-- 1. Registrar el rol del especialista mecánico en el sistema
ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'heavy_mechanic';

-- 2. ENUM para el ciclo de vida del defecto mecánico
CREATE TYPE defect_status AS ENUM ('reported', 'under_repair', 'rectified');

-- 3. Tabla forense de fallos mecánicos de planta
CREATE TABLE plant_defects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
    asset_id UUID NOT NULL REFERENCES assets(id) ON DELETE RESTRICT,
    reported_by UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    rectified_by UUID REFERENCES profiles(id) ON DELETE RESTRICT,
    
    defect_description TEXT NOT NULL,
    status defect_status NOT NULL DEFAULT 'reported',
    
    reported_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    rectified_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 4. Trigger Atómico: Sincronización del Inventario Base (SSOT)
CREATE OR REPLACE FUNCTION sync_asset_status_on_defect()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NEW.status IN ('reported', 'under_repair') THEN
        -- Retirar el camión/excavadora del juego operativo inmediatamente
        UPDATE assets 
        SET status = 'out_of_service'
        WHERE id = NEW.asset_id;
    ELSIF NEW.status = 'rectified' AND OLD.status != 'rectified' THEN
        -- Restaurar el camión al estado limpio listo para operar
        UPDATE assets 
        SET status = 'available'
        WHERE id = NEW.asset_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_asset_status_on_defect
    AFTER INSERT OR UPDATE OF status ON plant_defects
    FOR EACH ROW
    EXECUTE FUNCTION sync_asset_status_on_defect();

-- 5. Hard Lockout Trigger: Bloqueo de inicio de jornada
CREATE OR REPLACE FUNCTION check_active_defects_before_shift()
RETURNS TRIGGER 
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM plant_defects 
        WHERE asset_id = NEW.vehicle_id 
        AND status IN ('reported', 'under_repair')
    ) THEN
        RAISE EXCEPTION 'Red Tag Lockout: El activo se encuentra fuera de servicio por fallo mecánico crítico.';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_active_defects_shift
    BEFORE INSERT ON shift_assignments
    FOR EACH ROW
    EXECUTE FUNCTION check_active_defects_before_shift();

-- Configurar RLS para plant_defects
ALTER TABLE plant_defects ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Cualquiera puede ver defectos" ON plant_defects
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "Usuarios pueden reportar defectos" ON plant_defects
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = reported_by);

CREATE POLICY "Solo heavy_mechanic puede rectificar defectos" ON plant_defects
    FOR UPDATE TO authenticated 
    USING (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE profiles.id = auth.uid() AND profiles.role = 'heavy_mechanic'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE profiles.id = auth.uid() AND profiles.role = 'heavy_mechanic'
        )
    );
