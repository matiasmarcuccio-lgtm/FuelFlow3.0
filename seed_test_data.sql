SET session_replication_role = replica;

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
VALUES
('00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'authenticated', 'authenticated', 'admin@jitsite.com', crypt('password123', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated', 'driver@jitsite.com', crypt('password123', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '')
ON CONFLICT DO NOTHING;

INSERT INTO public.fleets (id, name, status) VALUES ('48432f69-952e-4536-bd5a-095a3d2bb8cf', 'Test Fleet', 'active') ON CONFLICT DO NOTHING;

INSERT INTO public.profiles (id, fleet_id, role) VALUES 
('11111111-1111-1111-1111-111111111111', '48432f69-952e-4536-bd5a-095a3d2bb8cf', 'fleet_manager'),
('22222222-2222-2222-2222-222222222222', '48432f69-952e-4536-bd5a-095a3d2bb8cf', 'driver')
ON CONFLICT (id) DO UPDATE SET fleet_id = EXCLUDED.fleet_id, role = EXCLUDED.role;

INSERT INTO public.license_categories (id, code, description) VALUES 
('33333333-3333-3333-3333-333333333333', 'HR', 'Heavy Rigid'),
('44444444-4444-4444-4444-444444444444', 'LV', 'Light Vehicle')
ON CONFLICT DO NOTHING;

INSERT INTO public.assets (id, fleet_id, internal_code, category, status, current_engine_hours, current_odometer, required_license_id) VALUES 
('55555555-5555-5555-5555-555555555555', '48432f69-952e-4536-bd5a-095a3d2bb8cf', 'DT-001', 'heavy_machinery', 'operational', 100, NULL, '33333333-3333-3333-3333-333333333333'),
('66666666-6666-6666-6666-666666666666', '48432f69-952e-4536-bd5a-095a3d2bb8cf', 'DT-002', 'heavy_machinery', 'operational', 100, NULL, '44444444-4444-4444-4444-444444444444')
ON CONFLICT DO NOTHING;

INSERT INTO public.driver_licenses (driver_id, license_category_id, issued_date, expiry_date) VALUES 
('22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333', '2020-01-01', '2030-01-01')
ON CONFLICT DO NOTHING;

INSERT INTO public.asset_assignments (fleet_id, asset_id, driver_id, assigned_by, shift_start, shift_end) VALUES 
('48432f69-952e-4536-bd5a-095a3d2bb8cf', '55555555-5555-5555-5555-555555555555', '22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', now() - INTERVAL '14 hours', now() - INTERVAL '1 hour')
ON CONFLICT DO NOTHING;

SET session_replication_role = DEFAULT;
