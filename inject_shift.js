const { Client } = require('pg');

async function run() {
  const client = new Client({
    connectionString: 'postgresql://postgres:postgres@127.0.0.1:5432/postgres'
  });
  
  try {
    await client.connect();
    
    // Check if the user exists and get their ID
    const res = await client.query(`SELECT id FROM auth.users WHERE email = 'driver@jitsite.com'`);
    if (res.rows.length === 0) {
      console.log('Driver not found');
      return;
    }
    const driverId = res.rows[0].id;
    
    const res2 = await client.query(`SELECT id FROM auth.users WHERE email = 'admin@jitsite.com'`);
    if (res2.rows.length === 0) {
      console.log('Admin not found');
      return;
    }
    const adminId = res2.rows[0].id;
    
    // 1. CLEAR FATIGUE LOG: Delete past shifts today so the driver is rested
    await client.query(`DELETE FROM public.asset_assignments WHERE driver_id = $1`, [driverId]);
    console.log('Cleared past shifts to bypass fatigue limit.');

    // 2. Insert a pending shift
    await client.query(`
      INSERT INTO public.asset_assignments (fleet_id, asset_id, driver_id, status, assigned_by) 
      VALUES (
        '48432f69-952e-4536-bd5a-095a3d2bb8cf', 
        '55555555-5555-5555-5555-555555555555', 
        $1, 
        'pending_prestart',
        $2
      )
    `, [driverId, adminId]);
    
    console.log('Successfully injected a pending shift for the driver.');
  } catch (err) {
    console.error('Error executing script:', err);
  } finally {
    await client.end();
  }
}

run();
