const { Client } = require('pg');

async function run() {
  const client = new Client({
    connectionString: 'postgresql://postgres:postgres@127.0.0.1:5432/postgres'
  });
  
  try {
    await client.connect();
    
    // Disable triggers for this session so handle_new_user doesn't crash on fake data
    await client.query(`SET session_replication_role = replica;`);
    
    // Create the supervisor user in auth.users
    await client.query(`
      INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
      VALUES
      ('00000000-0000-0000-0000-000000000000', '77777777-7777-7777-7777-777777777777', 'authenticated', 'authenticated', 'supervisor@jitsite.com', crypt('password123', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"role":"supervisor"}', now(), now(), '', '', '', '')
      ON CONFLICT (id) DO NOTHING;
    `);
    
    // Upsert into profiles
    await client.query(`
      INSERT INTO public.profiles (id, fleet_id, role, status) 
      VALUES ('77777777-7777-7777-7777-777777777777', '48432f69-952e-4536-bd5a-095a3d2bb8cf', 'supervisor', 'ACTIVE')
      ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, fleet_id = EXCLUDED.fleet_id
    `);
    
    // We also need to clear MFA for supervisor just in case
    await client.query(`DELETE FROM auth.mfa_factors WHERE user_id = '77777777-7777-7777-7777-777777777777'`);
    
    await client.query(`SET session_replication_role = DEFAULT;`);
    console.log('Successfully configured supervisor account.');
  } catch (err) {
    console.error('Error executing script:', err);
  } finally {
    await client.end();
  }
}

run();
