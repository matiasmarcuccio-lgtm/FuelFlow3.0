import { createClient } from '@supabase/supabase-js';

const url = process.env.VITE_SUPABASE_URL;
const key = process.env.VITE_SUPABASE_ANON_KEY;

if (!url || !key) {
    console.error('Missing URL or KEY');
    process.exit(1);
}

const supabase = createClient(url, key);

async function test() {
    console.log('Testing Supabase connection to:', url);
    
    // 1. Check assets
    const { data: assets, error: assetsErr } = await supabase.from('assets').select('id, asset_type, status, current_project_id');
    if (assetsErr) {
        console.error('Error fetching assets:', assetsErr.message);
    } else {
        console.log(`Found ${assets.length} assets.`);
        if (assets.length > 0) {
            console.log('Sample asset project ID:', assets[0].current_project_id);
        }
    }

    // 2. Try subscribing to realtime
    console.log('\nTesting realtime subscription...');
    const channel = supabase.channel('test_channel')
        .on('postgres_changes', { event: '*', schema: 'public', table: 'assets' }, (payload) => {
            console.log('Received payload:', payload);
        })
        .subscribe((status, err) => {
            console.log('Realtime status:', status);
            if (err) console.error('Realtime error:', err);
            process.exit(0);
        });
}

test();
