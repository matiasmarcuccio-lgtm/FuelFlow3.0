import pkg from 'pg';
const { Client } = pkg;
const client = new Client({
    connectionString: 'postgresql://postgres:postgres@127.0.0.1:5432/postgres'
});

async function run() {
    await client.connect();

    try {
        await client.query(`
            CREATE TABLE IF NOT EXISTS public.whs_overrides (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                supervisor_id UUID NOT NULL REFERENCES auth.users(id),
                driver_id UUID NOT NULL REFERENCES auth.users(id),
                document_path VARCHAR(2048) NOT NULL,
                new_expiry_date DATE NOT NULL,
                override_timestamp TIMESTAMPTZ DEFAULT now() NOT NULL
            );
            
            ALTER TABLE public.whs_overrides ENABLE ROW LEVEL SECURITY;
            
            CREATE OR REPLACE FUNCTION public.fn_block_whs_mutation()
            RETURNS TRIGGER AS $$
            BEGIN
                RAISE EXCEPTION 'FORENSIC_SEAL_VIOLATION: WHS overrides are immutable and cannot be updated or deleted.';
            END;
            $$ LANGUAGE plpgsql;

            DROP TRIGGER IF EXISTS trg_block_whs_mutation ON public.whs_overrides;
            CREATE TRIGGER trg_block_whs_mutation
            BEFORE UPDATE OR DELETE ON public.whs_overrides
            FOR EACH ROW EXECUTE FUNCTION public.fn_block_whs_mutation();
        `);

        // Need to create bucket if it doesn't exist, though it supposedly does, just in case.
        await client.query(`
            INSERT INTO storage.buckets (id, name, public) 
            VALUES ('compliance_docs', 'compliance_docs', false) 
            ON CONFLICT (id) DO NOTHING;
        `);

        await client.query(`
            DROP POLICY IF EXISTS "Command chain can upload compliance docs" ON storage.objects;
            CREATE POLICY "Command chain can upload compliance docs" ON storage.objects FOR INSERT TO authenticated
            WITH CHECK (
                bucket_id = 'compliance_docs' AND 
                EXISTS (
                    SELECT 1 FROM public.profiles 
                    WHERE id = auth.uid() 
                    AND role IN ('supervisor', 'fleet_manager', 'super_admin')
                )
            );
        `);

        await client.query(`
            CREATE OR REPLACE FUNCTION public.fn_verify_driver_insurance(p_driver_id UUID, p_expiry_date DATE, p_file_path VARCHAR)
            RETURNS BOOLEAN
            LANGUAGE plpgsql
            SECURITY DEFINER
            AS $$
            DECLARE
                v_role VARCHAR;
            BEGIN
                -- LINE 1: Role Validation
                SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();
                IF v_role NOT IN ('supervisor', 'fleet_manager', 'super_admin') THEN
                    RAISE EXCEPTION 'UNAUTHORIZED_WHS_OVERRIDE: You do not have the required authority level.';
                END IF;

                -- Step 1: Inject forensic seal
                INSERT INTO public.whs_overrides (supervisor_id, driver_id, document_path, new_expiry_date, override_timestamp)
                VALUES (auth.uid(), p_driver_id, p_file_path, p_expiry_date, now());

                -- Step 2: Update the driver profile
                UPDATE public.profiles
                SET insurance_expiry_date = p_expiry_date
                WHERE id = p_driver_id;

                RETURN true;
            END;
            $$;
        `);

        await client.query(`
            CREATE OR REPLACE FUNCTION public.check_insurance_compliance()
            RETURNS TRIGGER AS $$
            DECLARE
                v_target_id UUID;
            BEGIN
                v_target_id := COALESCE(NEW.driver_id, NEW.contractor_id);
                
                IF NOT (SELECT insurance_expiry_date > CURRENT_DATE FROM public.profiles WHERE id = v_target_id) THEN
                    RAISE EXCEPTION 'Operación bloqueada: Póliza expirada. Suba su documentación en la sección de cumplimiento.';
                END IF;
                
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;
            
            NOTIFY pgrst, 'reload schema';
        `);

        console.log('Backend WHS architecture deployed successfully');
    } catch (err) {
        console.error("Error executing queries:", err);
    } finally {
        await client.end();
    }
}
run();
