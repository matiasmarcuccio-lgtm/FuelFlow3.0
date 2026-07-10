-- ==========================================
-- JITSite / FuelFlow Seed Data (Topología Operativa)
-- ==========================================
-- Ejecutar DESPUÉS de haber inyectado los usuarios con scripts/seed-users.js

-- 1. PERFILES (Resolviendo dinámicamente los UUIDs de auth.users generados por GoTrue)
INSERT INTO public.profiles (id, full_name, role, status)
SELECT id, 'Alice (Super Admin)', 'super_admin', 'active' FROM auth.users WHERE email = 'admin@jitsite.com'
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role;

INSERT INTO public.profiles (id, full_name, role, status)
SELECT id, 'Bob (Fleet Manager)', 'fleet_manager', 'active' FROM auth.users WHERE email = 'fleet@jitsite.com'
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role;

INSERT INTO public.profiles (id, full_name, role, status)
SELECT id, 'Charlie (Supervisor)', 'supervisor', 'active' FROM auth.users WHERE email = 'supervisor@jitsite.com'
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role;

INSERT INTO public.profiles (id, full_name, role, status)
SELECT id, 'Dave (Operator)', 'operator', 'active' FROM auth.users WHERE email = 'operator@jitsite.com'
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role;

INSERT INTO public.profiles (id, full_name, role, status, hashed_pin)
SELECT id, 'Eve (Mechanic)', 'heavy_mechanic', 'active', crypt('1234', gen_salt('bf')) FROM auth.users WHERE email = 'fitter@jitsite.com'
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role, hashed_pin = EXCLUDED.hashed_pin;

INSERT INTO public.profiles (id, full_name, role, status)
SELECT id, 'Frank (Weighbridge)', 'weighbridge', 'active' FROM auth.users WHERE email = 'tollgate@jitsite.com'
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, role = EXCLUDED.role;
-- 2. PROYECTOS (Varianza Temporal Histórica para que business_metrics tenga datos reales)
-- Usamos NOW() - INTERVAL para generar historia.

-- Proyecto de hace 3 meses
INSERT INTO public.projects (id, name, client_name, project_type, start_date, estimated_end_date, status, created_at, loading_pad_geometry) 
VALUES (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 
  'Hobart Civil Construction Site', 
  'Tasmania Builders Co.', 
  'long_term', 
  CURRENT_DATE - INTERVAL '3 months', 
  CURRENT_DATE + INTERVAL '1 year', 
  'active', 
  NOW() - INTERVAL '3 months',
  ST_SetSRID(ST_GeomFromGeoJSON('{"type":"Polygon","coordinates":[[[147.3240,-42.8840],[147.3270,-42.8840],[147.3270,-42.8860],[147.3240,-42.8860],[147.3240,-42.8840]]]}'), 4326)
)
ON CONFLICT (id) DO UPDATE SET 
  name = EXCLUDED.name, 
  loading_pad_geometry = EXCLUDED.loading_pad_geometry;

-- Proyecto de hace 1 mes
INSERT INTO public.projects (id, name, client_name, project_type, start_date, estimated_end_date, status, created_at) 
VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Sandy Bay Fast Track Paving', 'City Council', 'short_term', CURRENT_DATE - INTERVAL '1 month', NULL, 'active', NOW() - INTERVAL '1 month')
ON CONFLICT (id) DO NOTHING;

-- Proyecto de esta semana (En planificación)
INSERT INTO public.projects (id, name, client_name, project_type, start_date, estimated_end_date, status, created_at) 
VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Launceston Highway Planning', 'Gov Infra', 'long_term', CURRENT_DATE + INTERVAL '2 weeks', CURRENT_DATE + INTERVAL '2 years', 'planning', NOW() - INTERVAL '2 days')
ON CONFLICT (id) DO NOTHING;


-- 3. VINCULAR SUPERVISORES A PROYECTOS (Integridad referencial y RLS)
-- Recuperamos el UUID real del supervisor 'Charlie' directamente de la tabla auth.users
INSERT INTO public.project_members (project_id, user_id, role)
SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', id, 'site_manager' FROM auth.users WHERE email = 'supervisor@jitsite.com'
ON CONFLICT (project_id, user_id) DO NOTHING;

INSERT INTO public.project_members (project_id, user_id, role)
SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', id, 'operator' FROM auth.users WHERE email = 'operator@jitsite.com'
ON CONFLICT (project_id, user_id) DO NOTHING;

INSERT INTO public.project_members (project_id, user_id, role)
SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', id, 'heavy_mechanic' FROM auth.users WHERE email = 'fitter@jitsite.com'
ON CONFLICT (project_id, user_id) DO NOTHING;

INSERT INTO public.project_members (project_id, user_id, role)
SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', id, 'weighbridge' FROM auth.users WHERE email = 'tollgate@jitsite.com'
ON CONFLICT (project_id, user_id) DO NOTHING;


-- 4. INVENTARIO DE ACTIVOS EN PROYECTO (Asignados a Bob, el Fleet Manager)
INSERT INTO public.assets (id, asset_code, registration_number, fleet_manager_id, current_project_id, asset_type, status, is_compliant, last_odometer_checkin)
SELECT 
    gen_random_uuid(), 'CRANE-001', 'TAS-123-CRN', id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'heavy_machinery', 'in_use', true, 12500 
FROM auth.users WHERE email = 'fleet@jitsite.com'
ON CONFLICT (asset_code) DO NOTHING;

INSERT INTO public.assets (id, asset_code, registration_number, fleet_manager_id, current_project_id, asset_type, status, is_compliant, last_odometer_checkin)
SELECT 
    gen_random_uuid(), 'TRUCK-045', 'TAS-999-TRK', id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'transport', 'in_use', true, 89000 
FROM auth.users WHERE email = 'fleet@jitsite.com'
ON CONFLICT (asset_code) DO NOTHING;

INSERT INTO public.assets (id, asset_code, registration_number, fleet_manager_id, current_project_id, asset_type, status, is_compliant, last_odometer_checkin)
SELECT 
    gen_random_uuid(), 'EXCAV-012', 'TAS-456-EXC', id, NULL, 'heavy_machinery', 'available', false, 4500 
FROM auth.users WHERE email = 'fleet@jitsite.com'
ON CONFLICT (asset_code) DO NOTHING;
