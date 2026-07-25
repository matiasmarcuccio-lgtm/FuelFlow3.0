import { createClient } from '@supabase/supabase-js';
const supabase = createClient('http://127.0.0.1:54321', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU');
async function run() {
    const { data: user } = await supabase.from('profiles').select('id').limit(1);
    const { error } = await supabase.from('master_orders').insert({
        material_type: 'Gravel Type A',
        target_tonnage: 5000,
        status: 'OPEN',
        origin_geofence: { type: 'Point', coordinates: [147.3240,-42.8840] },
        destination_geofence: { type: 'Point', coordinates: [147.3270,-42.8860] },
        requires_4x4_traction: false,
        max_turn_radius_m: 15.0,
        created_by: user?.[0]?.id || null
    });
    console.log(error ? error : 'Success');
}
run();
