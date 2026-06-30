


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."sync_watermelondb_push"("changes" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- 1. PROCESAR: fatigue_logs (Registro Legal Inmutable - NHVR)
    -- Regla: WatermelonDB solo puede CREAR. Se ignoran comandos de Update/Delete.
    IF changes ? 'fatigue_logs' THEN
        INSERT INTO fatigue_logs
        SELECT * FROM jsonb_populate_recordset(
            NULL::fatigue_logs, 
            changes->'fatigue_logs'->'created'
        );
    END IF;

    -- 2. PROCESAR: nhvr_compliance_logs (Pre-Start Checklist Inmutable)
    -- Regla: Solo inserción. Evidencia jurada del estado del vehículo antes de conducir.
    IF changes ? 'nhvr_compliance_logs' THEN
        INSERT INTO nhvr_compliance_logs
        SELECT * FROM jsonb_populate_recordset(
            NULL::nhvr_compliance_logs, 
            changes->'nhvr_compliance_logs'->'created'
        );
    END IF;

    -- 3. PROCESAR: expenses (Gastos y Tickets de Combustible - ATO)
    -- Regla: Flexible. El usuario puede registrar offline, pero también editar el monto 
    -- si el OCR de la cámara se equivocó, o borrar el gasto si lo duplicó.
    IF changes ? 'expenses' THEN
        
        -- A. Inserciones nuevas creadas sin conexión
        INSERT INTO expenses
        SELECT * FROM jsonb_populate_recordset(
            NULL::expenses, 
            changes->'expenses'->'created'
        );

        -- B. Actualizaciones (UPSERT para garantizar la modificación sin duplicar)
        INSERT INTO expenses
        SELECT * FROM jsonb_populate_recordset(
            NULL::expenses, 
            changes->'expenses'->'updated'
        )
        ON CONFLICT (id) DO UPDATE SET
            expense_category = EXCLUDED.expense_category,
            total_amount = EXCLUDED.total_amount,
            receipt_url = EXCLUDED.receipt_url,
            is_tax_deductible = EXCLUDED.is_tax_deductible,
            incurred_at = EXCLUDED.incurred_at;

        -- C. Borrados (WatermelonDB envía un arreglo de IDs)
        DELETE FROM expenses WHERE id IN (
            SELECT id::uuid FROM jsonb_array_elements_text(changes->'expenses'->'deleted')
        );
    END IF;

    -- Nota: Al estar dentro de un bloque BEGIN/END de PL/pgSQL, si cualquier inserción falla 
    -- (ej. el RLS rechaza el fleet_id, o falta una firma digital), PostgreSQL ejecuta un 
    -- ROLLBACK automático de TODAS las tablas. Cero registros huérfanos.

END;
$$;


ALTER FUNCTION "public"."sync_watermelondb_push"("changes" "jsonb") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."assets" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "registration_number" character varying(20) NOT NULL,
    "asset_type" character varying(50) NOT NULL,
    "fuel_burn_rate" numeric(5,2) NOT NULL,
    "max_fuel_capacity" numeric(8,2) NOT NULL,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."assets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."clients" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "legal_name" character varying(255) NOT NULL,
    "abn_number" character varying(14),
    "billing_email" character varying(255) NOT NULL,
    "payment_terms" character varying(50) DEFAULT 'Net 14'::character varying,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."clients" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."expenses" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "driver_id" "uuid",
    "trip_id" "uuid",
    "expense_category" character varying(50) NOT NULL,
    "total_amount" numeric(10,2) NOT NULL,
    "receipt_url" character varying(255),
    "is_tax_deductible" boolean DEFAULT true,
    "incurred_at" timestamp with time zone NOT NULL
);


ALTER TABLE "public"."expenses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fatigue_logs" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "driver_id" "uuid" NOT NULL,
    "event_type" character varying(50) NOT NULL,
    "latitude" numeric(10,8),
    "longitude" numeric(11,8),
    "logged_at" timestamp with time zone DEFAULT "now"(),
    "digital_signature_hash" character varying(255) NOT NULL
);


ALTER TABLE "public"."fatigue_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."invoices" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "trip_id" "uuid" NOT NULL,
    "invoice_number" character varying(50) NOT NULL,
    "total_amount" numeric(10,2) NOT NULL,
    "gst_amount" numeric(10,2) NOT NULL,
    "status" character varying(50) DEFAULT 'draft'::character varying,
    "due_date" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."invoices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."maintenance_schedules" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "service_type" character varying(100) NOT NULL,
    "interval_km" integer NOT NULL,
    "last_service_km" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."maintenance_schedules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nhvr_compliance_logs" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "driver_id" "uuid" NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "manual_odometer_reading" integer NOT NULL,
    "is_roadworthy" boolean NOT NULL,
    "defect_notes" "text",
    "declaration_timestamp" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."nhvr_compliance_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nodes" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "fleet_id" "uuid",
    "name" character varying(100) NOT NULL,
    "node_type" character varying(50) NOT NULL,
    "latitude" numeric(10,8) NOT NULL,
    "longitude" numeric(11,8) NOT NULL,
    "has_diesel_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."nodes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "fleet_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "role" character varying(50) NOT NULL,
    "full_name" character varying(255),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."service_logs" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "mechanic_node_id" "uuid" NOT NULL,
    "service_date" timestamp with time zone NOT NULL,
    "invoice_url" character varying(255),
    "is_verified" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."service_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sos_alerts" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "trip_id" "uuid" NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "diagnostic_type" character varying(50) NOT NULL,
    "latitude" numeric(10,8) NOT NULL,
    "longitude" numeric(11,8) NOT NULL,
    "status" character varying(50) DEFAULT 'broadcasting'::character varying,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."sos_alerts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."trip_waypoints" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "trip_id" "uuid" NOT NULL,
    "node_id" "uuid" NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "waypoint_order" integer NOT NULL,
    "waypoint_type" character varying(50) NOT NULL,
    "estimated_arrival" timestamp with time zone NOT NULL
);


ALTER TABLE "public"."trip_waypoints" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."trips" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "driver_id" "uuid",
    "asset_id" "uuid" NOT NULL,
    "status" character varying(50) DEFAULT 'scheduled'::character varying,
    "total_distance_km" numeric(10,2) NOT NULL,
    "estimated_fuel_required" numeric(10,2) NOT NULL,
    "scheduled_start" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."trips" OWNER TO "postgres";


ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_registration_number_key" UNIQUE ("registration_number");



ALTER TABLE ONLY "public"."clients"
    ADD CONSTRAINT "clients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fatigue_logs"
    ADD CONSTRAINT "fatigue_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_invoice_number_key" UNIQUE ("invoice_number");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."maintenance_schedules"
    ADD CONSTRAINT "maintenance_schedules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nhvr_compliance_logs"
    ADD CONSTRAINT "nhvr_compliance_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nodes"
    ADD CONSTRAINT "nodes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."service_logs"
    ADD CONSTRAINT "service_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sos_alerts"
    ADD CONSTRAINT "sos_alerts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."trip_waypoints"
    ADD CONSTRAINT "trip_waypoints_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."trips"
    ADD CONSTRAINT "trips_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."trips"
    ADD CONSTRAINT "fk_asset" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."maintenance_schedules"
    ADD CONSTRAINT "fk_asset" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."nhvr_compliance_logs"
    ADD CONSTRAINT "fk_asset" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."service_logs"
    ADD CONSTRAINT "fk_asset" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sos_alerts"
    ADD CONSTRAINT "fk_asset" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "fk_client" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."trips"
    ADD CONSTRAINT "fk_driver" FOREIGN KEY ("driver_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."service_logs"
    ADD CONSTRAINT "fk_mechanic_node" FOREIGN KEY ("mechanic_node_id") REFERENCES "public"."nodes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."trip_waypoints"
    ADD CONSTRAINT "fk_node" FOREIGN KEY ("node_id") REFERENCES "public"."nodes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "fk_trip" FOREIGN KEY ("trip_id") REFERENCES "public"."trips"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."trip_waypoints"
    ADD CONSTRAINT "fk_trip" FOREIGN KEY ("trip_id") REFERENCES "public"."trips"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sos_alerts"
    ADD CONSTRAINT "fk_trip" FOREIGN KEY ("trip_id") REFERENCES "public"."trips"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Insert own fatigue logs" ON "public"."fatigue_logs" FOR INSERT WITH CHECK (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Insert own fleet assets" ON "public"."assets" FOR INSERT WITH CHECK (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Insert own fleet compliance logs" ON "public"."nhvr_compliance_logs" FOR INSERT WITH CHECK (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Insert own fleet trips" ON "public"."trips" FOR INSERT WITH CHECK (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Insert own fleet waypoints" ON "public"."trip_waypoints" FOR INSERT WITH CHECK (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Manage own fleet clients" ON "public"."clients" USING (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Manage own fleet expenses" ON "public"."expenses" USING (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Manage own fleet invoices" ON "public"."invoices" USING (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Manage own fleet maintenance" ON "public"."maintenance_schedules" USING (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Manage own fleet service logs" ON "public"."service_logs" USING (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Manage own fleet sos alerts" ON "public"."sos_alerts" USING (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Update own fleet assets" ON "public"."assets" FOR UPDATE USING (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Update own fleet trips" ON "public"."trips" FOR UPDATE USING (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Users can update own profile" ON "public"."profiles" FOR UPDATE USING (("id" = "auth"."uid"()));



CREATE POLICY "Users can view own profile" ON "public"."profiles" FOR SELECT USING (("id" = "auth"."uid"()));



CREATE POLICY "View own fleet assets" ON "public"."assets" FOR SELECT USING (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "View own fleet compliance logs" ON "public"."nhvr_compliance_logs" FOR SELECT USING (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "View own fleet fatigue logs" ON "public"."fatigue_logs" FOR SELECT USING (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "View own fleet trips" ON "public"."trips" FOR SELECT USING (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "View own fleet waypoints" ON "public"."trip_waypoints" FOR SELECT USING (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "View public and own fleet nodes" ON "public"."nodes" FOR SELECT USING ((("fleet_id" IS NULL) OR ("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))));



ALTER TABLE "public"."assets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."clients" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."expenses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."fatigue_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."invoices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."maintenance_schedules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nhvr_compliance_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nodes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."service_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sos_alerts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."trip_waypoints" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."trips" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






















































































































































GRANT ALL ON FUNCTION "public"."sync_watermelondb_push"("changes" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."sync_watermelondb_push"("changes" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_watermelondb_push"("changes" "jsonb") TO "service_role";


















GRANT ALL ON TABLE "public"."assets" TO "anon";
GRANT ALL ON TABLE "public"."assets" TO "authenticated";
GRANT ALL ON TABLE "public"."assets" TO "service_role";



GRANT ALL ON TABLE "public"."clients" TO "anon";
GRANT ALL ON TABLE "public"."clients" TO "authenticated";
GRANT ALL ON TABLE "public"."clients" TO "service_role";



GRANT ALL ON TABLE "public"."expenses" TO "anon";
GRANT ALL ON TABLE "public"."expenses" TO "authenticated";
GRANT ALL ON TABLE "public"."expenses" TO "service_role";



GRANT ALL ON TABLE "public"."fatigue_logs" TO "anon";
GRANT ALL ON TABLE "public"."fatigue_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."fatigue_logs" TO "service_role";



GRANT ALL ON TABLE "public"."invoices" TO "anon";
GRANT ALL ON TABLE "public"."invoices" TO "authenticated";
GRANT ALL ON TABLE "public"."invoices" TO "service_role";



GRANT ALL ON TABLE "public"."maintenance_schedules" TO "anon";
GRANT ALL ON TABLE "public"."maintenance_schedules" TO "authenticated";
GRANT ALL ON TABLE "public"."maintenance_schedules" TO "service_role";



GRANT ALL ON TABLE "public"."nhvr_compliance_logs" TO "anon";
GRANT ALL ON TABLE "public"."nhvr_compliance_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."nhvr_compliance_logs" TO "service_role";



GRANT ALL ON TABLE "public"."nodes" TO "anon";
GRANT ALL ON TABLE "public"."nodes" TO "authenticated";
GRANT ALL ON TABLE "public"."nodes" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."service_logs" TO "anon";
GRANT ALL ON TABLE "public"."service_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."service_logs" TO "service_role";



GRANT ALL ON TABLE "public"."sos_alerts" TO "anon";
GRANT ALL ON TABLE "public"."sos_alerts" TO "authenticated";
GRANT ALL ON TABLE "public"."sos_alerts" TO "service_role";



GRANT ALL ON TABLE "public"."trip_waypoints" TO "anon";
GRANT ALL ON TABLE "public"."trip_waypoints" TO "authenticated";
GRANT ALL ON TABLE "public"."trip_waypoints" TO "service_role";



GRANT ALL ON TABLE "public"."trips" TO "anon";
GRANT ALL ON TABLE "public"."trips" TO "authenticated";
GRANT ALL ON TABLE "public"."trips" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































drop extension if exists "pg_net";


