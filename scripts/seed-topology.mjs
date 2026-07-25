import fs from 'fs';
import pkg from 'pg';
const { Client } = pkg;

const client = new Client({
  connectionString: 'postgresql://postgres:postgres@127.0.0.1:5432/postgres'
});

async function run() {
  await client.connect();
  const sql = fs.readFileSync('supabase/seed-topology.sql', 'utf8');
  await client.query(sql);
  await client.end();
  console.log('Topology seeded successfully');
}
run().catch(console.error);
