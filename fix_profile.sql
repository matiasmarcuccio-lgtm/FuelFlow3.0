-- 1. Crear una flota en estado moroso para la prueba visual
WITH nueva_flota AS (
    INSERT INTO public.fleets (id, name, status, created_at, updated_at)
    VALUES (gen_random_uuid(), 'Flota de Prueba Hobart B2B', 'past_due', now(), now())
    RETURNING id
)
-- 2. Inyectar el perfil para el UUID exacto que está fallando en tu consola F12
INSERT INTO public.profiles (id, role, fleet_id, full_name, created_at, updated_at)
SELECT 
    'a4d9424a-2afc-4eca-9abc-294e70ca9724'::uuid,
    'fleet_manager',
    nueva_flota.id,
    'Gerente Prueba B2B',
    now(),
    now()
FROM nueva_flota
ON CONFLICT (id) DO UPDATE 
SET role = 'fleet_manager',
    fleet_id = (SELECT id FROM public.fleets WHERE status = 'past_due' LIMIT 1);
