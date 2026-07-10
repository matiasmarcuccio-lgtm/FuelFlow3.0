-- 1. Iniciar una transacción para asegurar que la suplantación se revierta al terminar
BEGIN;

-- 2. Degradarse al rol base de Supabase para usuarios logueados
SET LOCAL ROLE authenticated;

-- 3. Inyectar el payload del JWT simulado
-- Reemplazo con el UUID real de Charlie que Node generó: '2d94909a-63e3-46d2-bb53-369c29cb2e0d'
SET LOCAL request.jwt.claims = '{"sub": "2d94909a-63e3-46d2-bb53-369c29cb2e0d", "role": "authenticated"}';

-- 4. Prueba de Intrusión (Zero-Trust): Intentar leer las métricas financieras
-- Si 'security_invoker = true' y RLS funcionan, esto DEBE ser repelido o devolver cero resultados.
SELECT * FROM business_metrics;

-- 5. Prueba de Acceso Legítimo: Intentar leer la topología de la obra
-- DEBE devolver únicamente los proyectos donde Charlie exista en 'project_members'.
SELECT id, name FROM projects;

-- 6. Destruir el contexto de la simulación y limpiar el entorno
ROLLBACK;
