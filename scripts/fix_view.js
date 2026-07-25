import { execSync } from 'child_process';

const queries = [
    `DROP VIEW IF EXISTS public.view_fleet_matrix;`,
    `CREATE VIEW public.view_fleet_matrix AS SELECT v.id as vehicle_id, v.registration_number, v.has_4x4_traction, v.turning_radius_m, v.max_payload_kg, v.status, v.is_compliant FROM public.assets v WHERE v.is_active = true AND v.status != 'maintenance';`,
    `NOTIFY pgrst, 'reload schema';`
];

for (const q of queries) {
    try {
        console.log("Executing:", q.substring(0, 50) + "...");
        execSync(`npx supabase db query "${q}"`, { stdio: 'inherit' });
    } catch (e) {
        console.error("Failed on query:", q);
        process.exit(1);
    }
}
console.log('Database integrity restored successfully');
