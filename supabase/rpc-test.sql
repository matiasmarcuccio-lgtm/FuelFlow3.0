-- Prueba como Charlie (Supervisor)
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub": "2d94909a-63e3-46d2-bb53-369c29cb2e0d", "role": "authenticated"}';
SELECT * FROM get_admin_business_metrics();
ROLLBACK;

-- Prueba como Alice (Super Admin)
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub": "89cb245c-2f12-4108-876b-999e8a4689f9", "role": "authenticated"}';
SELECT * FROM get_admin_business_metrics();
ROLLBACK;
