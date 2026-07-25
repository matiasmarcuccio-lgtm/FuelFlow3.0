const { Client } = require('pg');

async function run() {
  const client = new Client({
    connectionString: 'postgresql://postgres:postgres@127.0.0.1:5432/postgres'
  });
  
  try {
    await client.connect();
    
    // Create a default project
    await client.query(`
      INSERT INTO public.projects (id, name, status) 
      VALUES ('c7b3d8e0-5e0b-4b0f-8b3a-3b9f4b3d3b3d', 'Hobart Quarry - Default', 'ACTIVE')
      ON CONFLICT DO NOTHING;
    `);
    
    // Get supervisor ID
    const res = await client.query(`SELECT id FROM auth.users WHERE email = 'supervisor@jitsite.com'`);
    if (res.rows.length > 0) {
      const supervisorId = res.rows[0].id;
      // Assign supervisor to project
      await client.query(`
        INSERT INTO public.project_members (project_id, user_id, role) 
        VALUES ('c7b3d8e0-5e0b-4b0f-8b3a-3b9f4b3d3b3d', $1, 'supervisor')
        ON CONFLICT DO NOTHING;
      `, [supervisorId]);
      
      console.log('Successfully assigned supervisor to Hobart Quarry.');
    }
  } catch (err) {
    console.error('Error executing script:', err);
  } finally {
    await client.end();
  }
}

run();
