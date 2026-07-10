import fs from 'fs';
import pkg from 'pg';
const { Client } = pkg;
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.resolve(__dirname, '../apps/web/.env.local') });

async function run() {
    const client = new Client({
        connectionString: 'postgresql://postgres:postgres@127.0.0.1:5432/postgres'
    });
    await client.connect();
    
    const sql = fs.readFileSync(path.resolve(__dirname, '../supabase/seed-topology.sql'), 'utf-8');
    await client.query(sql);
    console.log('Topology seeded.');
    await client.end();
}

run().catch(console.error);
