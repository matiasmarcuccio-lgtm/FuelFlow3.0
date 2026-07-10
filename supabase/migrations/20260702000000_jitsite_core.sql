-- 1. Tablas de Usuarios y Roles
CREATE TABLE IF NOT EXISTS profiles (
    id UUID REFERENCES auth.users PRIMARY KEY,
    full_name TEXT,
    role TEXT CHECK (role IN ('super_admin', 'fleet_manager', 'supervisor', 'driver')),
    company_id UUID,
    status TEXT DEFAULT 'active'
);

-- 2. Proyectos (Soportando el modelo de precios corto/largo plazo)
CREATE TABLE IF NOT EXISTS projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    client_name TEXT,
    project_type TEXT CHECK (project_type IN ('short_term', 'long_term')),
    start_date DATE,
    estimated_end_date DATE,
    status TEXT DEFAULT 'planning',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2.5 Tabla puente para integridad referencial (Evita registros huérfanos)
CREATE TABLE IF NOT EXISTS project_members (
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT,
    PRIMARY KEY(project_id, user_id)
);

-- 3. Activos y su asignación (La "verdad" del inventario)
DROP TABLE IF EXISTS assets CASCADE;

CREATE TABLE assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_code TEXT UNIQUE NOT NULL,
    registration_number TEXT UNIQUE NOT NULL,
    fleet_manager_id UUID REFERENCES profiles(id) NOT NULL,
    current_project_id UUID REFERENCES projects(id),
    asset_type TEXT NOT NULL,
    status TEXT DEFAULT 'available',
    is_compliant BOOLEAN DEFAULT FALSE,
    last_odometer_checkin NUMERIC DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE assets ENABLE ROW LEVEL SECURITY;

-- Fleet Managers can manage their own assets
CREATE POLICY asset_fleet_manager_policy ON assets
    FOR ALL
    USING (fleet_manager_id = auth.uid());

-- Supervisors can read assets assigned to their projects
CREATE POLICY asset_supervisor_policy ON assets
    FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM project_members
        WHERE project_members.project_id = assets.current_project_id
        AND project_members.user_id = auth.uid()
    ));

-- 4. Handover y Auditoría (Seguridad CoR)
CREATE TABLE IF NOT EXISTS handover_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES projects(id),
    outgoing_user_id UUID REFERENCES auth.users(id),
    incoming_user_id UUID REFERENCES auth.users(id),
    open_incidents_count INT,
    signature_timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    signed_by_pin BOOLEAN DEFAULT TRUE
);

-- Función RPC de KPIs de Negocio para el Admin (Reemplaza la antigua vista vulnerable)
CREATE OR REPLACE FUNCTION get_admin_business_metrics()
RETURNS TABLE (
    active_users BIGINT,
    active_projects BIGINT,
    projected_mrr BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF (SELECT role FROM profiles WHERE id = auth.uid()) != 'super_admin' THEN
        RAISE EXCEPTION 'Access Denied: Super Admin privileges required.';
    END IF;

    RETURN QUERY
    SELECT
        (SELECT COUNT(DISTINCT id) FROM profiles)::BIGINT AS active_users,
        (SELECT COUNT(DISTINCT id) FROM projects WHERE status = 'active')::BIGINT AS active_projects,
        (SELECT COALESCE(SUM(CASE WHEN project_type = 'long_term' THEN 500 ELSE 1500 END), 0) FROM projects)::BIGINT AS projected_mrr;
END;
$$;

-- Activar RLS en proyectos
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;

-- Política: Los supervisores solo ven sus proyectos asignados
DROP POLICY IF EXISTS project_access_policy ON projects;
CREATE POLICY project_access_policy ON projects
    FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM project_members 
        WHERE project_members.project_id = projects.id 
        AND project_members.user_id = auth.uid()
    ));

-- Activar la transmisión de WebSockets para las tablas tácticas (Orquestador JIT)
ALTER PUBLICATION supabase_realtime ADD TABLE projects, assets, handover_logs;

-- =========================================================================
-- EVENT SOURCING: Telemetría Offline-First Inmutable y Resolución de Conflictos
-- =========================================================================

-- 1. Preparar la tabla principal para el control temporal
ALTER TABLE assets
ADD COLUMN IF NOT EXISTS last_telemetry_timestamp TIMESTAMP WITH TIME ZONE DEFAULT '1970-01-01 00:00:00+00';

-- 2. Crear la tabla inmutable de telemetría (El Libro Mayor Forense)
CREATE TABLE asset_telemetry_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID REFERENCES assets(id) ON DELETE CASCADE NOT NULL,
    recorded_by UUID REFERENCES profiles(id) NOT NULL,
    event_type TEXT NOT NULL, -- Ej: 'status_change', 'location_ping', 'odometer_update'
    payload JSONB NOT NULL, -- Estado mutado empaquetado por el frontend
    client_timestamp TIMESTAMP WITH TIME ZONE NOT NULL, -- La hora de la acción sin red
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() -- La hora de recepción del servidor
);

-- 3. Inyectar Blindaje RLS (El Verdadero Append-Only)
ALTER TABLE asset_telemetry_logs ENABLE ROW LEVEL SECURITY;

-- Los operarios solo pueden insertar sus propios eventos
CREATE POLICY telemetry_insert_policy ON asset_telemetry_logs
    FOR INSERT
    WITH CHECK (auth.uid() = recorded_by);

-- Fleet Managers y Super Admins pueden auditar, NADIE puede hacer UPDATE o DELETE
CREATE POLICY telemetry_select_policy ON asset_telemetry_logs
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM assets
            WHERE assets.id = asset_telemetry_logs.asset_id
            AND assets.fleet_manager_id = auth.uid()
        )
        OR
        (SELECT role FROM profiles WHERE id = auth.uid()) = 'super_admin'
    );

-- 4. El Orquestador de CQRS (Resolución de Conflictos Temporales)
CREATE OR REPLACE FUNCTION project_asset_telemetry_state()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Ejecuta con privilegios para modificar 'assets' sin bloquear al driver
AS $$
DECLARE
    current_asset_timestamp TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Extraer el último timestamp procesado de este activo específico
    SELECT last_telemetry_timestamp INTO current_asset_timestamp
    FROM assets
    WHERE id = NEW.asset_id;

    -- Resolución de conflictos: Proyectar el estado SOLO si el evento es cronológicamente superior
    IF NEW.client_timestamp > current_asset_timestamp THEN
        UPDATE assets
        SET
            status = COALESCE((NEW.payload->>'status'), status),
            last_odometer_checkin = COALESCE((NEW.payload->>'odometer')::NUMERIC, last_odometer_checkin),
            current_project_id = COALESCE((NEW.payload->>'project_id')::UUID, current_project_id),
            last_telemetry_timestamp = NEW.client_timestamp
        WHERE id = NEW.asset_id;
    END IF;

    -- Si el evento es un ping fantasma antiguo (client_timestamp inferior),
    -- se almacena en el log para auditoría, pero la tabla maestra 'assets' se ignora.
    RETURN NEW;
END;
$$;

-- 5. Vincular el Motor de Proyección
CREATE TRIGGER trg_project_asset_telemetry
    AFTER INSERT ON asset_telemetry_logs
    FOR EACH ROW
    EXECUTE FUNCTION project_asset_telemetry_state();

-- =========================================================================
-- CREW ROSTER SYNC: Validación offline inmutable (Web Crypto API support)
-- =========================================================================

-- 1. Añadir columnas criptográficas exclusivas para operaciones de campo
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS operational_pin_hash TEXT,
ADD COLUMN IF NOT EXISTS operational_pin_salt TEXT;

-- 2. Crear el RPC de sincronización de cuadrilla (Roster Sync)
CREATE OR REPLACE FUNCTION get_project_crew_hashes(p_project_id UUID)
RETURNS TABLE (
    user_id UUID,
    full_name TEXT,
    pin_hash TEXT,
    pin_salt TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER -- Permite leer los perfiles saltándose restricciones de lectura globales temporalmente
SET search_path = public
AS $$
BEGIN
    -- Validar que quien ejecuta esto sea realmente un supervisor o manager asignado a esta obra
    IF NOT EXISTS (
        SELECT 1 FROM project_members
        WHERE project_members.project_id = p_project_id
        AND project_members.user_id = auth.uid()
        AND project_members.role IN ('supervisor', 'fleet_manager')
    ) THEN
        RAISE EXCEPTION 'Access Denied: You are not authorized to sync this crew roster.';
    END IF;

    -- Retornar el diccionario criptográfico de los operarios vinculados a este proyecto
    RETURN QUERY
    SELECT
        p.id,
        p.full_name,
        p.operational_pin_hash,
        p.operational_pin_salt
    FROM profiles p
    JOIN project_members pm ON p.id = pm.user_id
    WHERE pm.project_id = p_project_id;
END;
$$;

-- =========================================================================
-- DLQ: Cola de Mensajes Muertos y RPC de Ingesta
-- =========================================================================

-- 1. Crear el libro mayor de excepciones (DLQ Real a nivel de datos)
CREATE TABLE IF NOT EXISTS telemetry_dead_letter_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID, -- Sin restricción FK rígida para asegurar que el dato corrupto se guarde
    recorded_by UUID,
    event_type TEXT,
    payload JSONB,
    client_timestamp TIMESTAMP WITH TIME ZONE,
    error_code TEXT,
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Asegurar RLS en la DLQ: Ningún operario puede leer ni alterar esto. 
-- Solo el Super Admin tiene acceso de lectura para auditoría forense.
ALTER TABLE telemetry_dead_letter_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY dlq_super_admin_select_policy ON telemetry_dead_letter_logs
    FOR SELECT USING ((SELECT role FROM profiles WHERE id = auth.uid()) = 'super_admin');

-- 2. Modificar el conducto de ingesta para atrapar fallos estructurales
CREATE OR REPLACE FUNCTION submit_telemetry_event(
    p_asset_id UUID,
    p_recorded_by UUID,
    p_event_type TEXT,
    p_payload JSONB,
    p_client_timestamp TIMESTAMP WITH TIME ZONE
)
RETURNS TEXT -- Retorna 'SUCCESS' o el código de error manejado por el sistema
LANGUAGE plpgsql
SECURITY DEFINER -- Ejecuta con privilegios del sistema para escribir en la DLQ sin exponer la tabla al rol public
SET search_path = public
AS $$
BEGIN
    -- Validar autenticación básica antes de procesar cualquier dato
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated';
    END IF;

    -- Intentar la inserción en el libro mayor inmutable
    INSERT INTO asset_telemetry_logs (
        asset_id,
        recorded_by,
        event_type,
        payload,
        client_timestamp
    ) VALUES (
        p_asset_id,
        p_recorded_by,
        p_event_type,
        p_payload,
        p_client_timestamp
    );

    RETURN 'SUCCESS';

EXCEPTION 
    -- Interceptar errores de integridad referencial, violaciones de checks o tipos malformados
    WHEN foreign_key_violation OR numeric_value_out_of_range OR check_violation OR data_exception THEN
        INSERT INTO telemetry_dead_letter_logs (
            asset_id,
            recorded_by,
            event_type,
            payload,
            client_timestamp,
            error_code,
            error_message
        ) VALUES (
            p_asset_id,
            p_recorded_by,
            p_event_type,
            p_payload,
            p_client_timestamp,
            SQLSTATE,
            SQLERRM
        );
        RETURN 'DEAD_LETTER_ROUTED';
    WHEN OTHERS THEN
        -- Errores inesperados de infraestructura crítica se relanzan para abortar
        RAISE;
END;
$$;
