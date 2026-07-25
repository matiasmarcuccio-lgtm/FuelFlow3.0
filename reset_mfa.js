const { Client } = require('pg');

async function run() {
  const client = new Client({
    connectionString: 'postgresql://postgres:postgres@127.0.0.1:5432/postgres'
  });
  
  try {
    await client.connect();
    
    // Check if the user exists and get their ID
    const res = await client.query(`SELECT id FROM auth.users WHERE email = 'admin@jitsite.com'`);
    if (res.rows.length === 0) {
      console.log('Admin not found');
      return;
    }
    const adminId = res.rows[0].id;
    
    // Delete all MFA factors for the admin to allow a clean re-enrollment
    await client.query(`DELETE FROM auth.mfa_factors WHERE user_id = $1`, [adminId]);
    await client.query(`DELETE FROM auth.mfa_challenges WHERE factor_id IN (SELECT id FROM auth.mfa_factors WHERE user_id = $1)`, [adminId]);
    // Note: the second delete might fail if foreign keys are cascade, or the first delete cascades to challenges.
    // The correct order is to delete challenges first if no cascade, but usually Supabase uses CASCADE.
    
    // Let's do it properly
    await client.query(`
      DELETE FROM auth.mfa_challenges 
      WHERE factor_id IN (SELECT id FROM auth.mfa_factors WHERE user_id = $1)
    `, [adminId]);

    await client.query(`
      DELETE FROM auth.mfa_amr_claims 
      WHERE session_id IN (SELECT id FROM auth.sessions WHERE user_id = $1)
    `, [adminId]);

    await client.query(`DELETE FROM auth.mfa_factors WHERE user_id = $1`, [adminId]);
    
    console.log('Successfully reset MFA factors for admin@jitsite.com');
  } catch (err) {
    console.error('Error executing script:', err);
  } finally {
    await client.end();
  }
}

run();
