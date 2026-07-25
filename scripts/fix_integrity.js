import { execSync } from 'child_process';

const queries = [
    `DROP POLICY IF EXISTS Allow_authenticated_users_to_view_profiles ON public.profiles;`,
    `CREATE OR REPLACE FUNCTION public.fn_is_command_chain() RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER AS $$ SELECT EXISTS ( SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('supervisor', 'fleet_manager', 'super_admin') ); $$;`,
    `CREATE POLICY Command_chain_can_view_profiles ON public.profiles FOR SELECT TO authenticated USING ( public.fn_is_command_chain() );`,
    `ALTER TABLE public.assets ADD COLUMN IF NOT EXISTS has_4x4_traction BOOLEAN DEFAULT false;`,
    `ALTER TABLE public.assets ADD COLUMN IF NOT EXISTS turning_radius_m NUMERIC DEFAULT 15.0;`,
    `ALTER TABLE public.assets ADD COLUMN IF NOT EXISTS max_payload_kg NUMERIC DEFAULT 10000;`,
    `ALTER TABLE public.assets ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;`,
    `UPDATE public.assets SET has_4x4_traction = true, turning_radius_m = 12.0, max_payload_kg = 50000;`,
    `CREATE OR REPLACE VIEW public.view_fleet_matrix AS SELECT v.id as vehicle_id, v.registration_number, v.has_4x4_traction, v.turning_radius_m, v.max_payload_kg, v.status, v.is_compliant FROM public.assets v WHERE v.is_active = true AND v.status != 'maintenance';`,
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
