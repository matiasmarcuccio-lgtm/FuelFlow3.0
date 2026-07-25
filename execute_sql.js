const { Client } = require('pg');
const fs = require('fs');

async function run() {
  const client = new Client({
    connectionString: 'postgresql://postgres:postgres@127.0.0.1:5432/postgres'
  });
  
  try {
    await client.connect();
    const sql = fs.readFileSync('seed_test_data.sql', 'utf8');
    await client.query(sql);
    console.log('Successfully executed seed_test_data.sql');
  } catch (err) {
    console.error('Error executing script:', err);
  } finally {
    await client.end();
  }
}

run();
