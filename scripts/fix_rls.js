import pkg from 'pg';
const { Client } = pkg;
const client = new Client({
    connectionString: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres'
});
async function run() {
    await client.connect();
    await client.query(`CREATE POLICY "Allow authenticated users to view profiles" ON public.profiles FOR SELECT TO authenticated USING (true);`);
    await client.query(`NOTIFY pgrst, 'reload schema';`);
    console.log('Success');
    await client.end();
}
run();
