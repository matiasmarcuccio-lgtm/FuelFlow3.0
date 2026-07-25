INSERT INTO public.profiles (id, role, full_name, fleet_id, status)
VALUES (
    '862622f9-9fc2-48fd-9325-9b7a36f0f52d',
    'fleet_manager',
    'Fleet Manager',
    '48432f69-952e-4536-bd5a-095a3d2bb8cf',
    'ACTIVE'
)
ON CONFLICT (id) DO UPDATE SET 
    role = 'fleet_manager', 
    fleet_id = '48432f69-952e-4536-bd5a-095a3d2bb8cf';
