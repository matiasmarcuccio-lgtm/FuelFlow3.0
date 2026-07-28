


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


CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "btree_gist" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "cube" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "earthdistance" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "postgis" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."asset_category" AS ENUM (
    'heavy_machinery',
    'light_vehicle',
    'static_plant'
);


ALTER TYPE "public"."asset_category" OWNER TO "postgres";


CREATE TYPE "public"."asset_status" AS ENUM (
    'operational',
    'maintenance',
    'decommissioned'
);


ALTER TYPE "public"."asset_status" OWNER TO "postgres";


CREATE TYPE "public"."assignment_status" AS ENUM (
    'active',
    'completed',
    'cancelled',
    'pending_prestart',
    'in_progress',
    'revoked'
);


ALTER TYPE "public"."assignment_status" OWNER TO "postgres";


CREATE TYPE "public"."cycle_status" AS ENUM (
    'loading',
    'in_transit',
    'dumped',
    'reconciled'
);


ALTER TYPE "public"."cycle_status" OWNER TO "postgres";


CREATE TYPE "public"."defect_category" AS ENUM (
    'hydraulic',
    'electrical',
    'engine',
    'wear_and_tear',
    'false_alarm'
);


ALTER TYPE "public"."defect_category" OWNER TO "postgres";


CREATE TYPE "public"."defect_status" AS ENUM (
    'reported',
    'under_repair',
    'rectified'
);


ALTER TYPE "public"."defect_status" OWNER TO "postgres";


CREATE TYPE "public"."excavator_status" AS ENUM (
    'ready_to_load',
    'relocating',
    'rock_breaking',
    'standby'
);


ALTER TYPE "public"."excavator_status" OWNER TO "postgres";


CREATE TYPE "public"."hire_model_type" AS ENUM (
    'dry_hire',
    'wet_hire'
);


ALTER TYPE "public"."hire_model_type" OWNER TO "postgres";


CREATE TYPE "public"."subscription_status" AS ENUM (
    'trialing',
    'active',
    'past_due',
    'canceled',
    'suspended'
);


ALTER TYPE "public"."subscription_status" OWNER TO "postgres";


CREATE TYPE "public"."subscription_tier" AS ENUM (
    'tier_1',
    'tier_2',
    'tier_3'
);


ALTER TYPE "public"."subscription_tier" OWNER TO "postgres";


CREATE TYPE "public"."user_role" AS ENUM (
    'contractor',
    'operator',
    'admin',
    'weighbridge_operator',
    'heavy_mechanic'
);


ALTER TYPE "public"."user_role" OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."load_offers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contractor_id" "uuid" NOT NULL,
    "crane_window_start" timestamp with time zone NOT NULL,
    "crane_window_end" timestamp with time zone NOT NULL,
    "destination_lat" numeric(10,8) NOT NULL,
    "destination_lng" numeric(11,8) NOT NULL,
    "requires_4x4_traction" boolean DEFAULT false,
    "max_turn_radius_m" numeric(4,2),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "status" character varying(20) DEFAULT 'BIDDING_OPEN'::character varying,
    "staging_area" "public"."geometry"(Polygon,4326),
    "active_excavation" "public"."geometry"(Polygon,4326),
    "exclusion_zone" "public"."geometry"(Polygon,4326),
    "completed_at_local" timestamp with time zone,
    "material_type" character varying(50),
    "is_hazardous" boolean DEFAULT false,
    "waste_certificate_id" character varying(100),
    "loaded_gross_mass" numeric,
    "docket_image_path" "text",
    "ocr_mass_extracted" numeric,
    "anomaly_flag" character varying(50),
    "anomaly_resolved_at" timestamp with time zone,
    "anomaly_resolved_by" "uuid",
    "anomaly_resolution_reason" "text",
    "anomaly_resolution_tags" "text"[],
    "master_order_id" "uuid",
    "driver_id" "uuid",
    "digital_bypass" boolean DEFAULT false,
    "bypassed_by" "uuid",
    "paper_docket_ref" character varying(100),
    CONSTRAINT "load_offers_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['BIDDING_OPEN'::character varying, 'BIDDING_LOCKED'::character varying, 'MANIFEST_PENDING'::character varying, 'COMPLETED'::character varying, 'AUDITED'::character varying])::"text"[])))
);


ALTER TABLE "public"."load_offers" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."active_excavation_geojson"("offer" "public"."load_offers") RETURNS "jsonb"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  SELECT ST_AsGeoJSON(offer.active_excavation)::jsonb;
$$;


ALTER FUNCTION "public"."active_excavation_geojson"("offer" "public"."load_offers") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."audit_log_changes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO access_logs (user_id, table_name, row_id, action)
  VALUES (auth.uid(), TG_TABLE_NAME, COALESCE(NEW.id, OLD.id), TG_OP);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."audit_log_changes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."audit_the_ocr_auditor"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT wo.id, wo.document_path, wo.override_timestamp, wo.supervisor_id
        FROM public.whs_overrides wo
        LEFT JOIN public.ocr_audit_logs oal ON wo.id = oal.override_id
        WHERE oal.id IS NULL
          AND wo.override_timestamp < (now() - interval '15 minutes')
    LOOP
        -- Inyectamos directamente a la Dead Letter Queue (Alertando Evasión de Auditoría)
        INSERT INTO public.dead_letter_queue (
            original_event_id, 
            event_type, 
            payload, 
            last_error
        ) VALUES (
            r.id,
            'OCR_AUDIT_EVASION',
            jsonb_build_object(
                'supervisor_id', r.supervisor_id,
                'document_path', r.document_path,
                'override_timestamp', r.override_timestamp,
                'message', 'CRITICAL ALERT: WHS Override was never audited by the Vision Edge Function (Timeout or Crash).'
            ),
            'Silent Deno failure or network partition detected.'
        );

        -- Opcional: Podríamos marcar el override en una tabla de estado, 
        -- pero la DLQ ya asegura que n8n despachará la alerta al Manager WHS.
    END LOOP;
END;
$$;


ALTER FUNCTION "public"."audit_the_ocr_auditor"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_buffered_loading_pad"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Si hay un polígono, inflarlo 5 metros (casteando a geography para precisión métrica)
    IF NEW.loading_pad_geometry IS NOT NULL THEN
        NEW.loading_pad_buffered := ST_Buffer(
            NEW.loading_pad_geometry::geography, 
            5.0 -- Tolerancia de histéresis en metros
        )::geometry;
    ELSE
        NEW.loading_pad_buffered := NULL;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."calculate_buffered_loading_pad"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_fleet_health_scores"("p_fleet_id" "uuid") RETURNS TABLE("asset_id" "uuid", "internal_code" character varying, "health_score" numeric, "critical_warnings" integer, "predicted_failure_days" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    WITH thermal_stress AS (
        -- Cuenta los picos térmicos menores a 105°C pero mayores a 95°C en los últimos 14 días
        SELECT m.asset_id, count(*) as stress_events
        FROM public.iot_telemetry_logs m
        WHERE m.temperature BETWEEN 95 AND 104
        AND m.created_at >= (now() - interval '14 days')
        GROUP BY m.asset_id
    ),
    minor_defects AS (
        -- Cuenta defectos marcados en Pre-Starts que no bloquearon la máquina
        SELECT a.asset_id, count(*) as defect_events
        FROM public.prestart_inspections a
        WHERE a.status = 'passed_with_warnings'
        AND a.created_at >= (now() - interval '14 days')
        GROUP BY a.asset_id
    )
    SELECT 
        ast.id,
        ast.internal_code,
        -- Cálculo del Health Score (Base 100)
        GREATEST(0, 100 - (COALESCE(ts.stress_events, 0) * 4.5) - (COALESCE(md.defect_events, 0) * 2.0))::NUMERIC as health_score,
        (COALESCE(ts.stress_events, 0) + COALESCE(md.defect_events, 0))::INT as critical_warnings,
        -- Predicción lineal simple de falla
        CASE 
            WHEN (COALESCE(ts.stress_events, 0) + COALESCE(md.defect_events, 0)) = 0 THEN 90
            ELSE GREATEST(1, (30 / (COALESCE(ts.stress_events, 0) + COALESCE(md.defect_events, 0))))::INT
        END as predicted_failure_days
    FROM public.assets ast
    LEFT JOIN thermal_stress ts ON ast.id = ts.asset_id
    LEFT JOIN minor_defects md ON ast.id = md.asset_id
    WHERE ast.fleet_id = p_fleet_id;
END;
$$;


ALTER FUNCTION "public"."calculate_fleet_health_scores"("p_fleet_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."certify_prestart"("p_assignment_id" "uuid", "p_brakes" boolean, "p_fluids" boolean, "p_structural" boolean, "p_is_safe" boolean, "p_defect_notes" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_caller_id UUID;
    v_assignment_record RECORD;
BEGIN
    v_caller_id := auth.uid();

    SELECT * INTO v_assignment_record 
    FROM public.asset_assignments 
    WHERE id = p_assignment_id FOR UPDATE;

    IF v_assignment_record.driver_id != v_caller_id THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_UNAUTHORIZED: Solo el operador asignado puede certificar el activo.';
    END IF;

    IF v_assignment_record.status != 'pending_prestart' THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_CONFLICT: El turno ya fue iniciado o cerrado.';
    END IF;

    -- Candado de Reloj del Servidor
    IF v_assignment_record.prestart_commenced_at IS NULL THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_VIOLATION: No se registró el inicio de la inspección en el servidor.';
    END IF;

    -- Aquí PostgreSQL evalúa prestart_time_friction usando SU propio reloj guardado
    INSERT INTO public.prestart_checks (
        assignment_id, operator_id, brakes_checked, fluids_checked, structural_checked, 
        is_safe_to_operate, defect_notes, inspection_started_at, inspection_completed_at
    ) VALUES (
        p_assignment_id, v_caller_id, p_brakes, p_fluids, p_structural, 
        p_is_safe, p_defect_notes, v_assignment_record.prestart_commenced_at, now()
    );

    IF p_is_safe THEN
        UPDATE public.asset_assignments 
        SET status = 'in_progress' 
        WHERE id = p_assignment_id;
    ELSE
        UPDATE public.asset_assignments 
        SET status = 'completed', shift_end = now() 
        WHERE id = p_assignment_id;
        
        UPDATE public.assets 
        SET status = 'maintenance' 
        WHERE id = v_assignment_record.asset_id;
        
        INSERT INTO public.maintenance_logs (asset_id, locked_by_uid, issue_description)
        VALUES (v_assignment_record.asset_id, v_caller_id, 'PRE-START FAILURE: ' || COALESCE(p_defect_notes, 'Unspecified hazard'));
    END IF;
END;
$$;


ALTER FUNCTION "public"."certify_prestart"("p_assignment_id" "uuid", "p_brakes" boolean, "p_fluids" boolean, "p_structural" boolean, "p_is_safe" boolean, "p_defect_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_active_defects_before_shift"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM plant_defects 
        WHERE asset_id = NEW.vehicle_id 
        AND status IN ('reported', 'under_repair')
    ) THEN
        RAISE EXCEPTION 'Red Tag Lockout: El activo se encuentra fuera de servicio por fallo mecánico crítico.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_active_defects_before_shift"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_insurance_compliance"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_target_id UUID;
BEGIN
    v_target_id := COALESCE(NEW.driver_id, NEW.contractor_id);
    
    -- Utilizando IS NOT TRUE para manejar NULL de forma estricta
    IF (SELECT insurance_expiry_date > CURRENT_DATE FROM public.profiles WHERE id = v_target_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Operación bloqueada: Póliza expirada. Suba su documentación en la sección de cumplimiento.';
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_insurance_compliance"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."close_active_shift"("p_assignment_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_shift RECORD;
    v_contract RECORD;
    v_hours_worked NUMERIC;
    v_billable_amount NUMERIC;
    v_certificate_id UUID;
BEGIN
    -- 1. Validar jurisdicción y estado
    SELECT * INTO v_shift FROM public.asset_assignments 
    WHERE id = p_assignment_id AND driver_id = auth.uid() AND status = 'in_progress'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_VIOLATION: No hay un turno en progreso válido para cerrar bajo tu jurisdicción.';
    END IF;

    -- 2. Obtener el contrato comercial asociado
    SELECT * INTO v_contract FROM public.billing_contracts 
    WHERE asset_id = v_shift.asset_id AND is_active = true LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'BILLING_ERROR: Activo sin contrato de facturación activo. Imposible liquidar.';
    END IF;

    -- 3. ESCUDO DE ENRUTAMIENTO ERP (La Nueva Frontera)
    IF v_contract.erp_contact_id IS NULL OR length(v_contract.erp_contact_id) < 2 THEN
        RAISE EXCEPTION 'ERP_MAPPING_MISSING: El contrato comercial no está vinculado a un cliente en Xero/SAP. El turno no puede cerrarse hasta que administración asigne un erp_contact_id.';
    END IF;

    -- 4. Calcular la termodinámica financiera
    v_hours_worked := EXTRACT(EPOCH FROM (now() - v_shift.created_at)) / 3600.0;
    
    IF v_hours_worked > v_contract.overtime_threshold_hours THEN
        v_billable_amount := (v_contract.overtime_threshold_hours * v_contract.hourly_rate_asset) + 
                             ((v_hours_worked - v_contract.overtime_threshold_hours) * (v_contract.hourly_rate_asset * v_contract.overtime_multiplier));
    ELSE
        v_billable_amount := v_hours_worked * v_contract.hourly_rate_asset;
    END IF;

    -- 5. Cerrar el turno y generar el certificado forense, sellando el ID del cliente
    UPDATE public.asset_assignments 
    SET status = 'completed', shift_end = now() 
    WHERE id = p_assignment_id;

    INSERT INTO public.execution_certificates (
        asset_assignment_id, total_hours, total_billable, telemetry_confidence, telemetry_source, billed_to_erp_id
    ) VALUES (
        p_assignment_id, ROUND(v_hours_worked, 2), ROUND(v_billable_amount, 2), 'high', 'human_kiosk', v_contract.erp_contact_id
    ) RETURNING id INTO v_certificate_id;

    RETURN jsonb_build_object('success', true, 'certificate_id', v_certificate_id, 'billable_amount', v_billable_amount);
END;
$$;


ALTER FUNCTION "public"."close_active_shift"("p_assignment_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."custom_access_token_hook"("event" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    claims jsonb;
    user_role text;
    user_fleet_id uuid;
    fleet_status text;
BEGIN
    claims := event->'claims';
    
    SELECT p.role, p.fleet_id, f.status 
    INTO user_role, user_fleet_id, fleet_status
    FROM public.profiles p
    LEFT JOIN public.fleets f ON p.fleet_id = f.id
    WHERE p.id = (event->>'user_id')::uuid;

    IF user_role IS NOT NULL THEN
        claims := jsonb_set(claims, '{user_role}', to_jsonb(user_role));
        claims := jsonb_set(claims, '{fleet_id}', to_jsonb(user_fleet_id));
        claims := jsonb_set(claims, '{subscription_status}', to_jsonb(fleet_status));
    END IF;

    event := jsonb_set(event, '{claims}', claims);
    RETURN event;
END;
$$;


ALTER FUNCTION "public"."custom_access_token_hook"("event" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."emergency_reset_mfa"("p_target_uid" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_actor_role TEXT;
BEGIN
    v_actor_role := current_setting('request.jwt.claims', true)::jsonb ->> 'user_role';

    -- Fricción Absoluta: Solo la máxima autoridad puede ejecutar esto
    IF v_actor_role != 'super_admin' THEN
        RAISE EXCEPTION 'CRITICAL: Solo un super administrador puede ejecutar el protocolo de rescate biométrico.';
    END IF;

    -- Eliminar todos los factores de autenticación del usuario objetivo en el núcleo de Supabase
    DELETE FROM auth.mfa_factors WHERE user_id = p_target_uid;
    DELETE FROM auth.mfa_amr_claims WHERE session_id IN (SELECT id FROM auth.sessions WHERE user_id = p_target_uid);
    
    -- Insertar huella forense inmutable de la acción
    INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
    VALUES (NULL, 'RESETEO MFA DE EMERGENCIA APLICADO AL UID: ' || p_target_uid, auth.uid(), 'closed');
END;
$$;


ALTER FUNCTION "public"."emergency_reset_mfa"("p_target_uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."exclusion_zone_geojson"("offer" "public"."load_offers") RETURNS "jsonb"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  SELECT ST_AsGeoJSON(offer.exclusion_zone)::jsonb;
$$;


ALTER FUNCTION "public"."exclusion_zone_geojson"("offer" "public"."load_offers") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."execute_instant_revocation"("p_target_uid" "uuid", "p_forensic_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_actor_role TEXT;
    v_target_email TEXT;
BEGIN
    v_actor_role := LOWER(COALESCE(current_setting('request.jwt.claims', true)::jsonb ->> 'user_role', ''));

    -- Escudo Jurisdiccional: Solo la alta jerarquía puede guillotinar identidades
    IF v_actor_role NOT IN ('fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE: Su JWT (%) carece de soberanía para revocar credenciales operativas.', v_actor_role
            USING ERRCODE = '42501';
    END IF;

    -- Prevenir auto-decapitación accidental o maliciosa
    IF p_target_uid = auth.uid() THEN
        RAISE EXCEPTION 'SUICIDE_PREVENTION: Un operador no puede revocar su propia sesión activa.';
    END IF;

    SELECT email INTO v_target_email FROM auth.users WHERE id = p_target_uid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'TARGET_NOT_FOUND: El UUID proporcionado no existe en el registro biométrico.';
    END IF;

    -- PASO ATÓMICO 1: Bloqueo perpetuo en el núcleo de GoTrue
    UPDATE auth.users
    SET banned_until = '2099-01-01 00:00:00+00'::timestamptz,
        updated_at = now()
    WHERE id = p_target_uid;

    -- PASO ATÓMICO 2: Destrucción física de sesiones y tokens de refresco activos
    DELETE FROM auth.sessions WHERE user_id = p_target_uid;
    DELETE FROM auth.refresh_tokens WHERE user_id = p_target_uid;

    -- PASO ATÓMICO 3: Marcado del perfil público para disparar el evento WebSocket
    UPDATE public.profiles
    SET role = 'revoked',
        fleet_id = NULL,
        updated_at = now()
    WHERE id = p_target_uid;

    -- PASO ATÓMICO 4: Registro forense inmutable (WORM)
    -- Usamos el UUID dummy para asset_id ya que es NOT NULL
    INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
    VALUES (
        '00000000-0000-0000-0000-000000000000', 
        'REVOCACIÓN DE IDENTIDAD APLICADA A: ' || v_target_email || ' (' || p_target_uid || '). RAZÓN: ' || p_forensic_reason, 
        auth.uid(), 
        'resolved'
    );

    RETURN jsonb_build_object(
        'success', true,
        'revoked_uid', p_target_uid,
        'revoked_email', v_target_email,
        'action', 'TERMINATED_AND_PURGED',
        'timestamp', now()
    );
END;
$$;


ALTER FUNCTION "public"."execute_instant_revocation"("p_target_uid" "uuid", "p_forensic_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_assign_asset_to_project"("p_load_offer_id" "uuid", "p_driver_id" "uuid", "p_asset_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_fatigue_hours NUMERIC;
  v_needs_4x4 BOOLEAN;
  v_max_radius NUMERIC;
  v_asset_4x4 BOOLEAN;
  v_asset_radius NUMERIC;
BEGIN
  -- 1. Fatigue Check
  SELECT hours_active INTO v_fatigue_hours FROM view_driver_fatigue WHERE driver_id = p_driver_id;
  IF v_fatigue_hours > 11 THEN
    RAISE EXCEPTION 'NHVR Fatigue Limit Exceeded: Driver has been active for over 11 hours.';
  END IF;

  -- 2. Terrain Compatibility Check
  SELECT requires_4x4_traction, max_turn_radius_m INTO v_needs_4x4, v_max_radius FROM load_offers WHERE id = p_load_offer_id;
  SELECT has_4x4_traction, turning_radius_m INTO v_asset_4x4, v_asset_radius FROM assets WHERE id = p_asset_id;

  IF v_needs_4x4 = true AND v_asset_4x4 = false THEN
    RAISE EXCEPTION 'Terrain Restriction: Project requires 4x4 traction.';
  END IF;

  IF v_asset_radius > v_max_radius THEN
    RAISE EXCEPTION 'Space Restriction: Vehicle turning radius exceeds project limits.';
  END IF;

  -- 3. Assign
  INSERT INTO assignments (load_offer_id, operator_id, assigned_at) VALUES (p_load_offer_id, p_driver_id, NOW());
  UPDATE load_offers SET status = 'PENDING' WHERE id = p_load_offer_id;
  
  RETURN TRUE;
END;
$$;


ALTER FUNCTION "public"."fn_assign_asset_to_project"("p_load_offer_id" "uuid", "p_driver_id" "uuid", "p_asset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_capture_daily_fleet_usage"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_fleet record;
    v_count int;
BEGIN
    FOR v_fleet IN SELECT id FROM public.fleets LOOP
        SELECT COUNT(*) INTO v_count
        FROM public.assets
        WHERE fleet_id = v_fleet.id AND status = 'operational';

        INSERT INTO public.fleet_billing_ledger (fleet_id, billing_date, active_asset_count)
        VALUES (v_fleet.id, CURRENT_DATE, v_count)
        ON CONFLICT (fleet_id, billing_date) 
        DO UPDATE SET active_asset_count = EXCLUDED.active_asset_count;
    END LOOP;
    
    PERFORM net.http_post(
        url := current_setting('app.settings.edge_function_base_url', true) || '/report-usage',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
        ),
        body := '{}'::jsonb
    );
END;
$$;


ALTER FUNCTION "public"."fn_capture_daily_fleet_usage"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_consume_fleet_invite"("p_token" character varying) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_invite RECORD;
    v_caller_uid UUID;
BEGIN
    v_caller_uid := auth.uid();
    
    -- ADUANA 0: Verificar identidad básica en el motor
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: La terminal carece de un JWT de dispositivo válido para reclamar una identidad.'
            USING ERRCODE = '40100';
    END IF;

    -- ADUANA 1: Bloqueo transaccional FOR UPDATE contra Double-Spending
    SELECT id, fleet_id, role, expires_at, consumed_at
    INTO v_invite
    FROM public.fleet_invites
    WHERE token = UPPER(TRIM(p_token))
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TOKEN_NOT_FOUND: El código % no existe en los registros del Command Center.', p_token
            USING ERRCODE = 'P0002';
    END IF;

    IF v_invite.consumed_at IS NOT NULL THEN
        RAISE EXCEPTION 'TOKEN_ALREADY_CONSUMED: Este código de enrolamiento ya fue utilizado.'
            USING ERRCODE = '40900';
    END IF;

    -- 🚨 CORREGIDO: Se eliminó la variable sobrante que causaba el error 42601
    IF v_invite.expires_at < now() THEN
        RAISE EXCEPTION 'TOKEN_EXPIRED: El código venció. Solicite la emisión de un nuevo token por SMS.'
            USING ERRCODE = '41000';
    END IF;

    -- TRANSACCIÓN ATÓMICA A: Quemar el token permanentemente
    UPDATE public.fleet_invites
    SET consumed_at = now(),
        consumed_by_uid = v_caller_uid
    WHERE id = v_invite.id;

    -- TRANSACCIÓN ATÓMICA B: Vincular la jurisdicción y el rol en la tabla pública de perfiles
    UPDATE public.profiles
    SET fleet_id = v_invite.fleet_id,
        role = LOWER(v_invite.role),
        updated_at = now()
    WHERE id = v_caller_uid;

    -- Fallback Defensivo: Si el perfil no existía, crearlo
    IF NOT FOUND THEN
        INSERT INTO public.profiles (id, full_name, role, fleet_id, created_at, updated_at)
        VALUES (
            v_caller_uid, 
            'terminal_' || substr(v_caller_uid::text, 1, 8) || '@jitsite.device', 
            LOWER(v_invite.role), 
            v_invite.fleet_id, 
            now(), 
            now()
        );
    END IF;

    -- (ELIMINADO: El log de auditoría que apuntaba a maintenance_logs)

    RETURN jsonb_build_object(
        'success', true,
        'fleet_id', v_invite.fleet_id,
        'assigned_role', LOWER(v_invite.role),
        'operator_uid', v_caller_uid,
        'timestamp', now()
    );
END;
$$;


ALTER FUNCTION "public"."fn_consume_fleet_invite"("p_token" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_default_project_site"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Si el frontend de React (Capa 8) no envía el ID de obra, asignamos el proyecto activo por defecto
    IF NEW.project_site_id IS NULL THEN
        SELECT id INTO NEW.project_site_id 
        FROM public.project_sites 
        WHERE fleet_id = NEW.fleet_id AND status = 'ACTIVE' 
        LIMIT 1;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_default_project_site"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_dispatch_shift"("p_master_order_id" "uuid", "p_driver_id" "uuid", "p_asset_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_fatigue_hours NUMERIC;
  v_shift_id UUID;
  v_master_order RECORD;
  v_asset RECORD;
BEGIN
  -- 1. Fatigue Check
  SELECT hours_active INTO v_fatigue_hours FROM view_driver_fatigue WHERE driver_id = p_driver_id;
  IF v_fatigue_hours > 11 THEN
    RAISE EXCEPTION 'NHVR Fatigue Limit Exceeded: Driver has been active for over 11 hours.';
  END IF;

  -- 2. Traer master order
  SELECT * INTO v_master_order FROM public.master_orders WHERE id = p_master_order_id;
  IF NOT FOUND OR v_master_order.status != 'OPEN' THEN
    RAISE EXCEPTION 'Master Order not found or not open.';
  END IF;

  -- 3. Terrain Check
  SELECT * INTO v_asset FROM public.assets WHERE id = p_asset_id;
  IF v_master_order.requires_4x4_traction = true AND v_asset.has_4x4_traction = false THEN
    RAISE EXCEPTION 'Terrain Restriction: Project requires 4x4 traction.';
  END IF;

  -- 4. Crear Asignación de Turno
  INSERT INTO public.shift_assignments (master_order_id, driver_id, vehicle_id, assigned_by) 
  VALUES (p_master_order_id, p_driver_id, p_asset_id, auth.uid())
  RETURNING id INTO v_shift_id;

  -- 5. Generar la PRIMERA Load Offer del bucle
  INSERT INTO public.load_offers (
    master_order_id,
    driver_id,
    status,
    material_type,
    requires_4x4_traction,
    max_turn_radius_m,
    created_at
  ) VALUES (
    v_master_order.id,
    p_driver_id,
    'PENDING',
    v_master_order.material_type,
    v_master_order.requires_4x4_traction,
    v_master_order.max_turn_radius_m,
    NOW()
  );

  RETURN v_shift_id;
END;
$$;


ALTER FUNCTION "public"."fn_dispatch_shift"("p_master_order_id" "uuid", "p_driver_id" "uuid", "p_asset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_elevate_user_role"("p_target_id" "uuid", "p_new_role" "text", "p_justification" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_executor_role TEXT;
    v_aal_level TEXT;
    v_previous_role TEXT;
BEGIN
    -- 2.1 Aserción Criptográfica de Hardware (AAL2) extraída directamente del JWT activo
    v_aal_level := current_setting('request.jwt.claims', true)::jsonb ->> 'aal';
    IF v_aal_level IS DISTINCT FROM 'aal2' THEN
        RAISE EXCEPTION 'AAL2 Required: MFA Hardware verification is strictly required for this operation.';
    END IF;

    -- 2.2 Validación Estricta de Identidad Ejecutora (Debe ser super_admin)
    SELECT role INTO v_executor_role FROM public.profiles WHERE id = auth.uid();
    IF v_executor_role IS DISTINCT FROM 'super_admin' THEN
        RAISE EXCEPTION 'Access Denied: Only a Super Admin can elevate roles.';
    END IF;

    -- 2.3 Validación Implacable de Jerarquías Fantasma (ENUM en código duro)
    IF p_new_role NOT IN ('driver', 'supervisor', 'fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'Invalid Role: Attempted to inject a ghost hierarchy. Operation aborted.';
    END IF;

    -- 2.4 Obtener el rol actual para el registro de auditoría
    SELECT role INTO v_previous_role FROM public.profiles WHERE id = p_target_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target user profile not found.';
    END IF;

    -- 2.5 Ejecutar la promoción
    UPDATE public.profiles
    SET role = p_new_role
    WHERE id = p_target_id;

    -- 2.6 Sellar la auditoría
    INSERT INTO public.role_audit_logs (
        target_user_id, granted_by_user_id, previous_role, new_role, action_type, justification
    ) VALUES (
        p_target_id, auth.uid(), v_previous_role, p_new_role, 'ELEVATION', p_justification
    );

    RETURN 'SUCCESS: Role elevated mathematically verified.';
END;
$$;


ALTER FUNCTION "public"."fn_elevate_user_role"("p_target_id" "uuid", "p_new_role" "text", "p_justification" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_emergency_override_lockout"("p_asset_id" "uuid", "p_override_reason" character varying, "p_manager_pin" character varying) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
    v_caller_role VARCHAR(50);
    v_caller_pin VARCHAR(255);
    v_victim_uid UUID;
    v_lockout_id UUID;
    v_fleet_id UUID;
BEGIN
    SELECT role, pin_hash INTO v_caller_role, v_caller_pin
    FROM public.profiles WHERE id = auth.uid();

    IF v_caller_role NOT IN ('fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'USURPACIÓN DE MANDATO: Solo el Fleet Manager o Super Admin pueden ejecutar una Ruptura de Candado WHS (Su rol actual en BD es: "%").', COALESCE(v_caller_role, 'NULO')
            USING ERRCODE = '42501';
    END IF;

    IF v_caller_pin IS NULL OR v_caller_pin != crypt(p_manager_pin, v_caller_pin) THEN
        RAISE EXCEPTION 'PIN GERENCIAL INVÁLIDO: Autenticación fallida. El PIN ingresado no coincide con su perfil en la base de datos.'
            USING ERRCODE = '28P01';
    END IF;

    IF p_override_reason NOT IN ('OPERARIO AUSENTE', 'EMERGENCIA OPERATIVA', 'FALLO DE TERMINAL') THEN
        RAISE EXCEPTION 'MOTIVO LEGAL INVÁLIDO: Debe declarar una justificación normada por WorkSafe.'
            USING ERRCODE = '22023';
    END IF;

    -- Tomamos el primer candado para la firma de la autopsia
    SELECT id, locked_by_operator_uid, fleet_id INTO v_lockout_id, v_victim_uid, v_fleet_id
    FROM public.asset_lockouts
    WHERE asset_id = p_asset_id AND status = 'ACTIVE'
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NINGÚN CANDADO ACTIVO: El activo % no figura inmovilizado en la tabla asset_lockouts.', p_asset_id
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.system_audit_logs (
        actor_uid,
        actor_role,
        action_type,
        target_table,
        target_record_id,
        payload_after
    ) VALUES (
        auth.uid(),
        v_caller_role,
        'WHS_EMERGENCY_LOCKOUT_OVERRIDE',
        'asset_lockouts',
        v_lockout_id,
        jsonb_build_object(
            'fleet_id', v_fleet_id,
            'victim_operator_uid', v_victim_uid,
            'override_reason', p_override_reason,
            'asset_id', p_asset_id,
            'timestamp_aest', NOW() AT TIME ZONE 'Australia/Hobart'
        )
    );

    -- [CORRECCIÓN MASS-OVERRIDE]: Destruimos TODOS los candados activos del camión a la vez
    UPDATE public.asset_lockouts
    SET status = 'OVERRIDDEN', released_at = NOW(), released_by_fitter_uid = auth.uid()
    WHERE asset_id = p_asset_id AND status = 'ACTIVE';

    UPDATE public.assets SET status = 'operational' WHERE id = p_asset_id;

    RETURN jsonb_build_object(
        'success', true, 
        'action', 'BREAK_GLASS_EXECUTED',
        'asset_id', p_asset_id, 
        'victim_uid', v_victim_uid,
        'reason', p_override_reason
    );
END;
$$;


ALTER FUNCTION "public"."fn_emergency_override_lockout"("p_asset_id" "uuid", "p_override_reason" character varying, "p_manager_pin" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_enforce_operator_validity"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_expires_at TIMESTAMPTZ;
BEGIN
    SELECT expires_at INTO v_expires_at FROM public.profiles WHERE id = auth.uid();
    IF v_expires_at IS NOT NULL AND NOW() > v_expires_at THEN
        RAISE EXCEPTION 'OPERADOR CADUCADO: Su contrato o licencia temporal venció el %. Acceso denegado por normativa WHS.', v_expires_at
            USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_enforce_operator_validity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_enforce_solvency_lockdown"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_status VARCHAR(50);
    v_grace TIMESTAMPTZ;
BEGIN
    SELECT UPPER(status::text), grace_period_until 
    INTO v_status, v_grace
    FROM public.fleets 
    WHERE id = NEW.fleet_id;

    -- Si no está activa o en prueba, evaluamos la ventana de gracia exactamente
    IF v_status NOT IN ('ACTIVE', 'TRIAL', 'TRIALING') THEN
        IF v_status = 'PAST_DUE' AND v_grace IS NOT NULL AND NOW() <= v_grace THEN
            -- Dentro del amortiguador de 72 horas: permitir operación física
            RETURN NEW;
        ELSE
            RAISE EXCEPTION 'BILLING_LOCKDOWN: Flota suspendida por insolvencia fiscal. El periodo de gracia expiró el % o la membresía fue cancelada.', COALESCE(v_grace::text, 'INMEDIATO')
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_enforce_solvency_lockdown"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_enforce_whs_lockout"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_active_lockout UUID;
BEGIN
    -- 🚨 CORRECCIÓN: Verificar 'maintenance' en vez de 'OUT_OF_SERVICE'
    IF OLD.status = 'maintenance' AND NEW.status != 'maintenance' THEN
        SELECT id INTO v_active_lockout FROM public.asset_lockouts WHERE asset_id = OLD.id AND status = 'ACTIVE' LIMIT 1;

        IF FOUND THEN
            RAISE EXCEPTION 'VIOLACIÓN DE ENCLAVAMIENTO WHS: La maquinaria % posee una Etiqueta de Peligro activa (Lockout ID: %). Debe ser liberada por un mecánico certificado antes de cambiar su estado.', OLD.id, v_active_lockout
                USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_enforce_whs_lockout"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_execute_haul_transition"("p_asset_id" "uuid", "p_action" character varying, "p_route_id" "uuid" DEFAULT NULL::"uuid", "p_material_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_caller_uid UUID;
    v_shift RECORD;
    v_cycle RECORD;
    v_asset RECORD;
    v_material RECORD;
    v_calc_tonnage NUMERIC(8,2) := 0.00;
    v_now TIMESTAMPTZ := now();
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Terminal carece de sesión AAL2 válida.' USING ERRCODE = '40100';
    END IF;

    -- =========================================================================
    -- ADUANA 1: ENCLAVAMIENTO CON EL RELOJ DE FATIGA (CONDUCTO 1)
    -- =========================================================================
    SELECT id, fleet_id, status INTO v_shift 
    FROM public.shift_logs 
    WHERE operator_uid = v_caller_uid AND status = 'ACTIVE'
    ORDER BY started_at DESC LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'WHS_INTERLOCK: Prohibido iniciar o mutar ciclos de acarreo sin una jornada laboral ACTIVA en el reloj de fatiga.' 
            USING ERRCODE = '42501';
    END IF;

    -- Verificar que la maquinaria esté asignada y operativa
    SELECT id, fleet_id, status, hopper_capacity_m3 INTO v_asset 
    FROM public.assets WHERE id = p_asset_id FOR UPDATE;

    IF NOT FOUND OR v_asset.fleet_id != v_shift.fleet_id THEN
        RAISE EXCEPTION 'ASSET_VIOLATION: Maquinaria inexistente o fuera de su jurisdicción.' USING ERRCODE = '42501';
    END IF;

    IF v_asset.status = 'OUT_OF_SERVICE' THEN
        RAISE EXCEPTION 'WHS_LOCKOUT: La maquinaria se encuentra INHABILITADA por seguridad. Prohibido cargar material.' USING ERRCODE = '42501';
    END IF;

    -- Consultar si ya existe un ciclo activo para este camión
    SELECT * INTO v_cycle FROM public.haul_cycles 
    WHERE asset_id = p_asset_id AND state NOT IN ('COMPLETED', 'ABORTED')
    FOR UPDATE;

    -- =========================================================================
    -- MÁQUINA DE ESTADOS INDUSTRIAL: TRANSICIONES INMUTABLES
    -- =========================================================================
    IF p_action = 'START_LOADING' THEN
        IF FOUND THEN
            RAISE EXCEPTION 'CYCLE_IN_PROGRESS: El camión ya se encuentra en estado %. Cierre el ciclo actual antes de iniciar una nueva carga.', v_cycle.state
                USING ERRCODE = '40900';
        END IF;

        IF p_route_id IS NULL OR p_material_id IS NULL THEN
            RAISE EXCEPTION 'PARAM_REQUIRED: Debe indicar ruta y tipo de material para posicionarse en excavadora.' USING ERRCODE = '22023';
        END IF;

        INSERT INTO public.haul_cycles (fleet_id, asset_id, operator_uid, shift_id, route_id, material_id, state, started_at)
        VALUES (v_shift.fleet_id, p_asset_id, v_caller_uid, v_shift.id, p_route_id, p_material_id, 'LOADING', v_now)
        RETURNING * INTO v_cycle;

        UPDATE public.assets SET status = 'DISPATCHED', updated_at = v_now WHERE id = p_asset_id;

        RETURN jsonb_build_object('success', true, 'state', 'LOADING', 'cycle_id', v_cycle.id, 'started_at', v_now);

    ELSIF p_action = 'FINISH_LOADING' THEN
        IF NOT FOUND OR v_cycle.state != 'LOADING' THEN
            RAISE EXCEPTION 'TRANSITION_ERROR: No puede iniciar tránsito sin haber estado en carga (LOADING).' USING ERRCODE = '40000';
        END IF;

        -- CÁLCULO MATEMÁTICO DE TONELAJE (Volumen Tolva x Densidad Material)
        SELECT density_kg_m3 INTO v_material FROM public.materials WHERE id = v_cycle.material_id;
        IF FOUND THEN
            v_calc_tonnage := (COALESCE(v_asset.hopper_capacity_m3, 18.00) * v_material.density_kg_m3) / 1000.0;
        END IF;

        UPDATE public.haul_cycles 
        SET state = 'HAULING', loaded_at = v_now, tonnage_moved = v_calc_tonnage 
        WHERE id = v_cycle.id;

        RETURN jsonb_build_object('success', true, 'state', 'HAULING', 'tonnage_moved', v_calc_tonnage);

    ELSIF p_action = 'CONFIRM_DUMP' THEN
        IF NOT FOUND OR v_cycle.state != 'HAULING' THEN
            RAISE EXCEPTION 'TRANSITION_ERROR: Prohibido descargar sin haber completado la carga y el tránsito.' USING ERRCODE = '40000';
        END IF;

        UPDATE public.haul_cycles SET state = 'RETURNING', dumped_at = v_now WHERE id = v_cycle.id;

        RETURN jsonb_build_object('success', true, 'state', 'RETURNING', 'dumped_at', v_now);

    ELSIF p_action = 'COMPLETE_CYCLE' THEN
        IF NOT FOUND OR v_cycle.state != 'RETURNING' THEN
            RAISE EXCEPTION 'TRANSITION_ERROR: No puede cerrar ciclo sin haber vaciado la tolva en destino.' USING ERRCODE = '40000';
        END IF;

        UPDATE public.haul_cycles 
        SET state = 'COMPLETED', completed_at = v_now,
            cycle_duration_seconds = EXTRACT(EPOCH FROM (v_now - v_cycle.started_at))::INT
        WHERE id = v_cycle.id;

        -- Devolver camión a estado disponible para el siguiente ciclo
        UPDATE public.assets SET status = 'AVAILABLE', updated_at = v_now WHERE id = p_asset_id;

        RETURN jsonb_build_object(
            'success', true, 'state', 'COMPLETED', 
            'tonnage_added', v_cycle.tonnage_moved,
            'duration_seconds', EXTRACT(EPOCH FROM (v_now - v_cycle.started_at))::INT
        );

    ELSIF p_action = 'ABORT' THEN
        IF NOT FOUND THEN RETURN jsonb_build_object('success', true, 'state', 'ABORTED'); END IF;
        
        UPDATE public.haul_cycles SET state = 'ABORTED', completed_at = v_now WHERE id = v_cycle.id;
        UPDATE public.assets SET status = 'AVAILABLE', updated_at = v_now WHERE id = p_asset_id;
        
        RETURN jsonb_build_object('success', true, 'state', 'ABORTED', 'msg', 'Ciclo cancelado.');
    END IF;

    RAISE EXCEPTION 'UNKNOWN_ACTION: La directiva % no es reconocida por el motor de despacho.', p_action USING ERRCODE = '22023';
END;
$$;


ALTER FUNCTION "public"."fn_execute_haul_transition"("p_asset_id" "uuid", "p_action" character varying, "p_route_id" "uuid", "p_material_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_execute_haul_transition"("p_asset_id" "uuid", "p_action" character varying, "p_route_id" "uuid" DEFAULT NULL::"uuid", "p_material_id" "uuid" DEFAULT NULL::"uuid", "p_client_timestamp" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_caller_uid UUID := auth.uid();
    v_shift RECORD; v_cycle RECORD; v_asset RECORD; v_material RECORD;
    v_calc_tonnage NUMERIC(8,2) := 0.00;
    
    -- El servidor respeta la marca de tiempo de IndexedDB enviada por la cabina.
    -- Si no existe (ataque o error), usa now().
    v_now TIMESTAMPTZ := COALESCE(p_client_timestamp, now());
BEGIN
    -- Validaciones estándar de aduana...
    IF v_caller_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

    SELECT id, fleet_id, status INTO v_shift FROM public.shift_logs 
    WHERE operator_uid = v_caller_uid AND status = 'ACTIVE' ORDER BY started_at DESC LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'WHS_INTERLOCK'; END IF;

    SELECT id, fleet_id, status, hopper_capacity_m3 INTO v_asset 
    FROM public.assets WHERE id = p_asset_id FOR UPDATE;

    SELECT * INTO v_cycle FROM public.haul_cycles 
    WHERE asset_id = p_asset_id AND state NOT IN ('COMPLETED', 'ABORTED') FOR UPDATE;

    IF p_action = 'START_LOADING' THEN
        INSERT INTO public.haul_cycles (fleet_id, asset_id, operator_uid, shift_id, route_id, material_id, state, started_at)
        VALUES (v_shift.fleet_id, p_asset_id, v_caller_uid, v_shift.id, p_route_id, p_material_id, 'LOADING', v_now)
        RETURNING * INTO v_cycle;
        UPDATE public.assets SET status = 'DISPATCHED', updated_at = v_now WHERE id = p_asset_id;
        RETURN jsonb_build_object('success', true, 'state', 'LOADING', 'started_at', v_now);
        
    ELSIF p_action = 'FINISH_LOADING' THEN
        SELECT density_kg_m3 INTO v_material FROM public.materials WHERE id = v_cycle.material_id;
        IF FOUND THEN v_calc_tonnage := (COALESCE(v_asset.hopper_capacity_m3, 18.00) * v_material.density_kg_m3) / 1000.0; END IF;
        
        UPDATE public.haul_cycles SET state = 'HAULING', loaded_at = v_now, tonnage_moved = v_calc_tonnage WHERE id = v_cycle.id;
        RETURN jsonb_build_object('success', true, 'state', 'HAULING', 'tonnage_moved', v_calc_tonnage);
        
    ELSIF p_action = 'CONFIRM_DUMP' THEN
        UPDATE public.haul_cycles SET state = 'RETURNING', dumped_at = v_now WHERE id = v_cycle.id;
        RETURN jsonb_build_object('success', true, 'state', 'RETURNING', 'dumped_at', v_now);
        
    ELSIF p_action = 'COMPLETE_CYCLE' THEN
        UPDATE public.haul_cycles 
        SET state = 'COMPLETED', completed_at = v_now,
            cycle_duration_seconds = GREATEST(1, EXTRACT(EPOCH FROM (v_now - v_cycle.started_at))::INT)
        WHERE id = v_cycle.id;
        UPDATE public.assets SET status = 'AVAILABLE', updated_at = v_now WHERE id = p_asset_id;
        RETURN jsonb_build_object('success', true, 'state', 'COMPLETED', 'tonnage_added', v_cycle.tonnage_moved);
        
    ELSIF p_action = 'ABORT' THEN
        UPDATE public.haul_cycles SET state = 'ABORTED', completed_at = v_now WHERE id = v_cycle.id;
        UPDATE public.assets SET status = 'AVAILABLE', updated_at = v_now WHERE id = p_asset_id;
        RETURN jsonb_build_object('success', true, 'state', 'ABORTED');
    END IF;
    
    RAISE EXCEPTION 'UNKNOWN_ACTION';
END;
$$;


ALTER FUNCTION "public"."fn_execute_haul_transition"("p_asset_id" "uuid", "p_action" character varying, "p_route_id" "uuid", "p_material_id" "uuid", "p_client_timestamp" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_execute_shift_action"("p_action" character varying, "p_asset_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_caller_uid UUID;
    v_caller_role VARCHAR(50);
    v_caller_fleet UUID;
    v_shift RECORD;
    v_asset_status VARCHAR(50);
    v_now TIMESTAMPTZ := now();
    v_elapsed_seconds INT;
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN RAISE EXCEPTION 'SESIÓN FANTASMA: Petición anónima bloqueada por Zero-Trust.' USING ERRCODE = '28000'; END IF;

    SELECT role, fleet_id INTO v_caller_role, v_caller_fleet FROM public.profiles WHERE id = v_caller_uid;

    -- Obtener turno activo si existe
    SELECT * INTO v_shift FROM public.shift_logs 
    WHERE operator_uid = v_caller_uid AND status IN ('ACTIVE', 'FATIGUE_LOCKOUT', 'BREAK_MANDATORY')
    ORDER BY created_at DESC LIMIT 1 FOR UPDATE;

    IF p_action = 'START_SHIFT' THEN
        IF v_shift IS NOT NULL THEN RAISE EXCEPTION 'WHS_VIOLATION: Ya existe un turno activo para este operador.' USING ERRCODE = '23505'; END IF;
        
        -- Insertar turno inmutable
        INSERT INTO public.shift_logs (operator_uid, fleet_id, asset_id, status)
        VALUES (v_caller_uid, v_caller_fleet, p_asset_id, 'ACTIVE')
        RETURNING id INTO v_shift.id;

        RETURN jsonb_build_object('success', true, 'action', p_action, 'shift_id', v_shift.id, 'status', 'ACTIVE');
    
    ELSIF p_action = 'CHECK_STATUS' THEN
        IF v_shift IS NULL THEN RAISE EXCEPTION 'NO_ACTIVE_SHIFT' USING ERRCODE = '02000'; END IF;

        -- Evaluar Guillotina de Fatiga (WorkSafe Tasmania: Max 5 hrs continuas, simularemos 5 hrs como 18000s)
        IF v_shift.status = 'ACTIVE' THEN
            v_elapsed_seconds := EXTRACT(EPOCH FROM (v_now - v_shift.last_state_change_at))::INT;
            
            IF (v_shift.continuous_work_seconds + v_elapsed_seconds) >= 18000 THEN
                -- EJECUCIÓN DE GUILLOTINA FÍSICA
                UPDATE public.shift_logs 
                SET status = 'FATIGUE_LOCKOUT', 
                    accumulated_work_seconds = accumulated_work_seconds + v_elapsed_seconds,
                    continuous_work_seconds = continuous_work_seconds + v_elapsed_seconds,
                    last_state_change_at = v_now
                WHERE id = v_shift.id;

                -- Enclavamiento Físico del Vehículo (Si aplica)
                IF v_shift.asset_id IS NOT NULL THEN
                    UPDATE public.assets SET status = 'maintenance', updated_at = v_now WHERE id = v_shift.asset_id;
                    
                    -- Alerta automática al Fleet Manager
                    INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
                    VALUES (v_shift.asset_id, 'ALERTA FATIGA WHS: UID ' || v_caller_uid || ' BLOQUEADO POR EXCEDER HORAS MÁXIMAS.', v_caller_uid, 'in_progress');
                END IF;

                RETURN jsonb_build_object('success', false, 'status', 'FATIGUE_LOCKOUT', 'msg', 'INTERLOCK ACTIVADO POR EXCESO DE FATIGA.');
            END IF;
        END IF;

        RETURN jsonb_build_object('success', true, 'status', v_shift.status, 'continuous_seconds', v_shift.continuous_work_seconds);

    ELSIF p_action = 'END_SHIFT' THEN
        IF v_shift IS NULL THEN RAISE EXCEPTION 'NO_ACTIVE_SHIFT' USING ERRCODE = '02000'; END IF;

        v_elapsed_seconds := EXTRACT(EPOCH FROM (v_now - v_shift.last_state_change_at))::INT;

        UPDATE public.shift_logs 
        SET status = 'COMPLETED',
            accumulated_work_seconds = accumulated_work_seconds + v_elapsed_seconds,
            continuous_work_seconds = continuous_work_seconds + v_elapsed_seconds,
            ended_at = v_now
        WHERE id = v_shift.id;

        -- Liberar la máquina si estaba bloqueada solo por fatiga
        IF v_shift.asset_id IS NOT NULL AND v_shift.status = 'FATIGUE_LOCKOUT' THEN
            UPDATE public.assets SET status = 'operational', updated_at = v_now WHERE id = v_shift.asset_id;
        END IF;

        RETURN jsonb_build_object('success', true, 'status', 'COMPLETED');
    ELSE
        RAISE EXCEPTION 'ACCIÓN NO RECONOCIDA: %', p_action USING ERRCODE = '22023';
    END IF;
END;
$$;


ALTER FUNCTION "public"."fn_execute_shift_action"("p_action" character varying, "p_asset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_export_regulatory_report"("p_report_type" character varying) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_caller_role VARCHAR(50);
    v_caller_fleet UUID;
    v_result JSONB;
BEGIN
    SELECT role, fleet_id INTO v_caller_role, v_caller_fleet 
    FROM public.profiles WHERE id = auth.uid();

    IF v_caller_role NOT IN ('super_admin', 'fleet_manager') THEN
        RAISE EXCEPTION 'JURISDICCIÓN DENEGADA: Solo gerencia puede generar paquetes de auditoría legal.'
            USING ERRCODE = '42501';
    END IF;

    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_ato_fuel_rebate_ledger;
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_predictive_maintenance_roster;
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_whs_compliance_audit;

    IF p_report_type = 'ATO_FUEL_REBATE' THEN
        SELECT jsonb_agg(to_jsonb(r.*)) INTO v_result FROM public.mv_ato_fuel_rebate_ledger r WHERE r.fleet_id = v_caller_fleet;
    ELSIF p_report_type = 'WHS_FATIGUE_AUDIT' THEN
        SELECT jsonb_agg(to_jsonb(w.*)) INTO v_result FROM public.mv_whs_compliance_audit w WHERE w.fleet_id = v_caller_fleet;
    ELSIF p_report_type = 'PREDICTIVE_MAINTENANCE' THEN
        SELECT jsonb_agg(to_jsonb(m.*)) INTO v_result FROM public.mv_predictive_maintenance_roster m WHERE m.fleet_id = v_caller_fleet;
    
    -- [CORRECCIÓN FORENSE]: Reemplazado p.email por p.full_name
    ELSIF p_report_type = 'WHS_BREAK_GLASS_AUDIT' THEN
        SELECT jsonb_agg(to_jsonb(t.*)) INTO v_result
        FROM (
            SELECT 
                l.created_at AT TIME ZONE 'Australia/Hobart' AS timestamp_aest,
                l.actor_uid AS gerente_ejecutor_uid,
                p.full_name AS gerente_nombre,
                l.target_record_id AS lockout_id_afectado,
                l.payload_after->>'asset_id' AS vehiculo_id,
                l.payload_after->>'victim_operator_uid' AS tecnico_atropellado_uid,
                l.payload_after->>'override_reason' AS motivo_worksafe
            FROM public.system_audit_logs l
            LEFT JOIN public.profiles p ON p.id = l.actor_uid
            WHERE l.action_type = 'WHS_EMERGENCY_LOCKOUT_OVERRIDE'
            AND l.payload_after->>'fleet_id' = v_caller_fleet::text
            ORDER BY l.created_at DESC
        ) t;
    ELSE
        RAISE EXCEPTION 'INVALID_REPORT_TYPE: % no existe en el catálogo de exportación.', p_report_type USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
    VALUES (NULL, 'EXPORTACIÓN FORENSE GENERADA [' || p_report_type || '] POR USUARIO ' || auth.uid(), auth.uid(), 'resolved');

    RETURN jsonb_build_object('success', true, 'report_type', p_report_type, 'fleet_id', v_caller_fleet, 'generated_at', now(), 'data', COALESCE(v_result, '[]'::jsonb));
END;
$$;


ALTER FUNCTION "public"."fn_export_regulatory_report"("p_report_type" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_fleet_can_operate"() RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_can_operate BOOLEAN;
BEGIN
    SELECT CASE 
        WHEN UPPER(status::text) IN ('ACTIVE', 'TRIAL', 'TRIALING') THEN true
        WHEN UPPER(status::text) = 'PAST_DUE' AND grace_period_until IS NOT NULL AND NOW() <= grace_period_until THEN true
        ELSE false
    END INTO v_can_operate
    FROM public.fleets
    WHERE id = (SELECT fleet_id FROM public.profiles WHERE id = auth.uid());
    
    RETURN COALESCE(v_can_operate, false);
END;
$$;


ALTER FUNCTION "public"."fn_fleet_can_operate"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_generate_fleet_invite"("p_fleet_id" "uuid") RETURNS character varying
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_token VARCHAR(10);
BEGIN
    -- Verificar si el usuario que llama tiene rol FLEET_MANAGER
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role IN ('fleet_manager', 'super_admin')
    ) THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE';
    END IF;

    -- Generar token simple (6 caracteres alfanuméricos en mayúsculas)
    v_token := UPPER(SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 6));

    INSERT INTO public.fleet_invites (fleet_id, token, created_by, role)
    VALUES (p_fleet_id, v_token, auth.uid(), 'driver');

    RETURN v_token;
END;
$$;


ALTER FUNCTION "public"."fn_generate_fleet_invite"("p_fleet_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_get_caller_fleet_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
    SELECT fleet_id FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$$;


ALTER FUNCTION "public"."fn_get_caller_fleet_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_guard_asset_site_transfer"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    IF NEW.project_site_id != OLD.project_site_id THEN
        IF EXISTS (SELECT 1 FROM public.asset_lockouts WHERE asset_id = OLD.id AND status = 'ACTIVE') THEN
            RAISE EXCEPTION 'TRASLADO BLOQUEADO POR WHS: El activo % tiene un candado LOTO activo. Debe ser liberado o sobreescrito por gerencia antes de transportarlo a otra obra.', OLD.id
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_guard_asset_site_transfer"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_guard_profile_privileges"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_actor_role TEXT;
BEGIN
    IF (NEW.role IS NOT DISTINCT FROM OLD.role) AND (NEW.fleet_id IS NOT DISTINCT FROM OLD.fleet_id) THEN
        NEW.updated_at := now();
        RETURN NEW;
    END IF;
    IF current_user IN ('postgres', 'supabase_admin', 'service_role') THEN
        NEW.updated_at := now();
        RETURN NEW;
    END IF;

    v_actor_role := LOWER(COALESCE(current_setting('request.jwt.claims', true)::jsonb ->> 'user_role', ''));

    IF v_actor_role != 'super_admin' THEN
        RAISE EXCEPTION 'SECURITY_VIOLATION: Elevación de privilegios denegada. Su JWT (%) carece de soberanía para alterar la columna role o fleet_id.', v_actor_role
            USING ERRCODE = '42501';
    END IF;

    NEW.updated_at := now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_guard_profile_privileges"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_inject_retroactive_docket"("p_master_order_id" "uuid", "p_driver_id" "uuid", "p_loaded_gross_mass" numeric, "p_paper_docket_ref" character varying, "p_docket_image_path" character varying) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_inserted_id UUID;
BEGIN
    -- Validaciones
    IF p_master_order_id IS NULL OR p_driver_id IS NULL OR p_loaded_gross_mass IS NULL OR p_paper_docket_ref IS NULL OR p_docket_image_path IS NULL THEN
        RAISE EXCEPTION 'All forensic fields are mandatory for a Bypass Injection.';
    END IF;

    -- Authorization validation
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('FLEET_MANAGER', 'SUPER_ADMIN')) THEN
        RAISE EXCEPTION 'Unauthorized: Only Fleet Managers or Super Admins can inject bypass dockets.';
    END IF;

    INSERT INTO public.load_offers (
        master_order_id,
        driver_id,
        status,
        loaded_gross_mass,
        digital_bypass,
        bypassed_by,
        paper_docket_ref,
        docket_image_path,
        created_at,
        completed_at_local
    ) VALUES (
        p_master_order_id,
        p_driver_id,
        'COMPLETED',
        p_loaded_gross_mass,
        true,
        auth.uid(),
        p_paper_docket_ref,
        p_docket_image_path,
        NOW(),
        NOW()
    ) RETURNING id INTO v_inserted_id;

    RETURN v_inserted_id;
END;
$$;


ALTER FUNCTION "public"."fn_inject_retroactive_docket"("p_master_order_id" "uuid", "p_driver_id" "uuid", "p_loaded_gross_mass" numeric, "p_paper_docket_ref" character varying, "p_docket_image_path" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_override_pin_lockout"("p_target_operator_uid" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_actor_role TEXT;
BEGIN
    SELECT LOWER(role) INTO v_actor_role FROM public.profiles WHERE id = auth.uid();

    -- Esclusa Zero-Trust: Solo jerarquía superior puede indultar bloqueos de seguridad
    IF v_actor_role NOT IN ('fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'JURISDICCIÓN DENEGADA: Su sesión carece de autoridad para restablecer terminales bloqueadas.'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.profiles
    SET pin_failed_attempts = 0,
        pin_locked_until = NULL,
        updated_at = now()
    WHERE id = p_target_operator_uid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TARGET_NOT_FOUND: El perfil del operador no existe en el catálogo.' USING ERRCODE = 'P0002';
    END IF;

    -- Registro en libro mayor forense
    INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
    VALUES (
        NULL,
        'INDULTO ADMINISTRATIVO DE PIN APLICADO POR ' || auth.uid() || ' FAVOR DE OPERARIO ' || p_target_operator_uid,
        auth.uid(),
        'closed'
    );

    RETURN jsonb_build_object('success', true, 'unlocked_uid', p_target_operator_uid, 'timestamp', now());
END;
$$;


ALTER FUNCTION "public"."fn_override_pin_lockout"("p_target_operator_uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_override_shift_assignment"("p_absent_driver_id" "uuid", "p_reserve_driver_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_current_shift RECORD;
BEGIN
    -- Validar permisos del solicitante
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role IN ('FLEET_MANAGER', 'SUPER_ADMIN')
    ) THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE';
    END IF;

    -- Obtener el turno activo del conductor ausente
    SELECT * INTO v_current_shift
    FROM public.shift_assignments
    WHERE driver_id = p_absent_driver_id AND status = 'ACTIVE'
    LIMIT 1 FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NO_ACTIVE_SHIFT';
    END IF;

    -- Graceful Shutdown: Cerrar el turno del conductor ausente
    UPDATE public.shift_assignments
    SET 
        status = 'COMPLETED',
        detach_reason = 'SHIFT_OVERRIDE',
        updated_at = NOW()
    WHERE id = v_current_shift.id;

    -- Iniciar el nuevo turno para el conductor de reserva heredando vehículo y orden maestra
    INSERT INTO public.shift_assignments (
        fleet_id,
        driver_id,
        vehicle_id,
        master_order_id,
        status,
        intent_to_detach
    ) VALUES (
        v_current_shift.fleet_id,
        p_reserve_driver_id,
        v_current_shift.vehicle_id,
        v_current_shift.master_order_id,
        'ACTIVE',
        false
    );

    RETURN true;
END;
$$;


ALTER FUNCTION "public"."fn_override_shift_assignment"("p_absent_driver_id" "uuid", "p_reserve_driver_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_promote_to_account_owner"("p_user_uid" "uuid", "p_fleet_name" character varying, "p_stripe_customer_id" character varying, "p_stripe_subscription_id" character varying) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_new_fleet_id UUID;
    v_current_role VARCHAR(50);
BEGIN
    SELECT role INTO v_current_role FROM public.profiles WHERE id = p_user_uid;
    
    IF v_current_role != 'pending_onboarding' THEN
        RAISE EXCEPTION 'ALERTA DE SEGURIDAD: El usuario % no está en limbo de onboarding (Rol actual: %)', p_user_uid, v_current_role
            USING ERRCODE = '42501';
    END IF;

    -- A. Crear la flota minera con estado comercial activo
    INSERT INTO public.fleets (
        name, stripe_customer_id, stripe_subscription_id, subscription_status, created_at
    ) VALUES (
        p_fleet_name, p_stripe_customer_id, p_stripe_subscription_id, 'ACTIVE', NOW()
    ) RETURNING id INTO v_new_fleet_id;

    -- B. Crear automáticamente la Obra Principal por defecto en la cantera
    INSERT INTO public.project_sites (
        fleet_id, name, status, vault_status, created_at
    ) VALUES (
        v_new_fleet_id, 'Obra Principal Hobart (Heredada)', 'ACTIVE', 'OPERATIONAL', NOW()
    );

    -- C. Ascender al usuario a account_owner y vincularlo a su nueva flota
    UPDATE public.profiles
    SET role = 'account_owner', fleet_id = v_new_fleet_id
    WHERE id = p_user_uid;

    RETURN jsonb_build_object(
        'success', true,
        'fleet_id', v_new_fleet_id,
        'promoted_uid', p_user_uid,
        'fleet_name', p_fleet_name
    );
END;
$$;


ALTER FUNCTION "public"."fn_promote_to_account_owner"("p_user_uid" "uuid", "p_fleet_name" character varying, "p_stripe_customer_id" character varying, "p_stripe_subscription_id" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_release_asset_lockout"("p_lockout_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_caller_role VARCHAR(50);
    v_lockout_owner UUID;
    v_owner_role VARCHAR(50);
    v_asset_id UUID;
BEGIN
    SELECT role INTO v_caller_role FROM public.profiles WHERE id = auth.uid();

    IF v_caller_role != 'fitter' THEN
        RAISE EXCEPTION 'JURISDICCIÓN DENEGADA: Solo mecánicos (fitter) pueden liberar candados LOTO estándar.'
            USING ERRCODE = '42501';
    END IF;

    SELECT l.locked_by_operator_uid, l.asset_id, p.role 
    INTO v_lockout_owner, v_asset_id, v_owner_role
    FROM public.asset_lockouts l
    LEFT JOIN public.profiles p ON p.id = l.locked_by_operator_uid
    WHERE l.id = p_lockout_id AND l.status = 'ACTIVE';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'CANDADO INEXISTENTE O INACTIVO: El registro % no está activo en el sistema.', p_lockout_id
            USING ERRCODE = '22023';
    END IF;

    -- Un Fitter solo libera su propio candado o el candado automático de un Driver (Pre-Start fallido).
    IF v_lockout_owner != auth.uid() AND v_owner_role != 'driver' THEN
        RAISE EXCEPTION 'BLOQUEO CRUZADO ILEGAL: No puede remover el candado LOTO instalado por otro mecánico (UUID: %). Requiere Ruptura de Emergencia Gerencial.', v_lockout_owner
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.asset_lockouts
    SET status = 'RELEASED', released_at = NOW(), released_by_operator_uid = auth.uid()
    WHERE id = p_lockout_id;

    IF NOT EXISTS (SELECT 1 FROM public.asset_lockouts WHERE asset_id = v_asset_id AND status = 'ACTIVE') THEN
        UPDATE public.assets SET status = 'operational' WHERE id = v_asset_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'lockout_id', p_lockout_id, 'released_at', NOW());
END;
$$;


ALTER FUNCTION "public"."fn_release_asset_lockout"("p_lockout_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_release_asset_lockout"("p_asset_id" "uuid", "p_resolution_notes" "text", "p_fitter_pin" character varying) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
    v_caller_uid UUID;
    v_actor_profile RECORD;
    v_active_lockout RECORD;
    v_asset_fleet_id UUID;
BEGIN
    v_caller_uid := auth.uid();

    -- ADUANA 0: Autenticación activa requerida
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: No hay sesión activa en el terminal del taller.'
            USING ERRCODE = '40100';
    END IF;

    -- ADUANA 1: Verificar identidad, jurisdicción de flota y rol soberano
    SELECT fleet_id, role, pin_hash, full_name
    INTO v_actor_profile 
    FROM public.profiles 
    WHERE id = v_caller_uid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'PROFILE_NOT_FOUND: Su identidad no existe en el catálogo biométrico.'
            USING ERRCODE = 'P0002';
    END IF;

    -- Solo un Fitter (mecánico), un Fleet Manager o un Super Admin pueden retirar una Etiqueta de Peligro
    IF v_actor_profile.role NOT IN ('fitter', 'fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'JURISDICCIÓN DENEGADA: Su rol (%) carece de licencia WHS para liberar maquinaria inhabilitada.', UPPER(v_actor_profile.role)
            USING ERRCODE = '42501';
    END IF;

    -- ADUANA 2: Firma Criptográfica Biometric/PIN (El blindaje anti-tablet abandonada)
    IF v_actor_profile.pin_hash IS NULL THEN
        RAISE EXCEPTION 'PIN_NOT_SET: Debe configurar su PIN militar antes de poder firmar indultos mecánicos.'
            USING ERRCODE = '42501';
    END IF;

    IF v_actor_profile.pin_hash != public.crypt(p_fitter_pin, v_actor_profile.pin_hash) THEN
        RAISE EXCEPTION 'PIN_INVALIDO: Firma criptográfica rechazada. El PIN introducido no coincide con el sello del técnico.'
            USING ERRCODE = '42501';
    END IF;

    -- ADUANA 3: Validar directiva legal de reparación
    IF p_resolution_notes IS NULL OR length(trim(p_resolution_notes)) < 10 THEN
        RAISE EXCEPTION 'NOTE_TOO_SHORT: Normativa minera exige al menos 10 caracteres describiendo la reparación técnica o sustitución de piezas ejecutada.'
            USING ERRCODE = '22023';
    END IF;

    -- ADUANA 4: Bloquear la Etiqueta de Peligro para evitar liberaciones concurrentes (Double-Release)
    SELECT id, fleet_id, lockout_reason, locked_by_operator_uid 
    INTO v_active_lockout 
    FROM public.asset_lockouts 
    WHERE asset_id = p_asset_id AND status = 'ACTIVE' 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'LOCKOUT_NOT_FOUND: La maquinaria % no posee ninguna Etiqueta de Peligro activa en este momento.', p_asset_id
            USING ERRCODE = 'P0002';
    END IF;

    -- Aislamiento de Flota (Un mecánico de la Flota A no puede liberar camiones de la Flota B)
    IF v_actor_profile.role != 'super_admin' AND v_active_lockout.fleet_id != v_actor_profile.fleet_id THEN
        RAISE EXCEPTION 'CROSS_FLEET_VIOLATION: Carece de jurisdicción para operar sobre activos de una flota ajena.'
            USING ERRCODE = '42501';
    END IF;

    -- =========================================================================
    -- SECUENCIA ATÓMICA DE LIBERACIÓN (EL ORDEN FÍSICO ES CRÍTICO)
    -- =========================================================================

    -- PASO A: Cortar el candado en la tabla de bloqueos PRIMERO.
    -- Si intentamos cambiar el estado de la máquina antes de esto, nuestro propio 
    -- disparador anti-sabotaje (trg_enforce_whs_lockout) detectará el candado y abortará todo.
    UPDATE public.asset_lockouts
    SET status = 'RELEASED',
        released_at = now(),
        released_by_fitter_uid = v_caller_uid,
        resolution_notes = UPPER(trim(p_resolution_notes))
    WHERE id = v_active_lockout.id;

    -- PASO B: Con la etiqueta liberada, restauramos la maquinaria al estado operativo
    UPDATE public.assets
    SET status = 'AVAILABLE',
        updated_at = now()
    WHERE id = p_asset_id;

    -- PASO C: Cerrar y sellar las órdenes de trabajo urgentes en el libro mayor de mantenimiento
    UPDATE public.maintenance_logs
    SET status = 'closed',
        issue_description = issue_description || ' | 🔧 RESUELTO POR FITTER [' || UPPER(COALESCE(v_actor_profile.full_name, 'DESCONOCIDO')) || ']: ' || UPPER(trim(p_resolution_notes))
    WHERE asset_id = p_asset_id AND status = 'open';

    -- Retorno limpio de telemetría para la interfaz de Vite
    RETURN jsonb_build_object(
        'success', true,
        'action', 'ASSET_RELEASED_TO_SERVICE',
        'asset_id', p_asset_id,
        'lockout_id', v_active_lockout.id,
        'released_by_uid', v_caller_uid,
        'fitter_name', UPPER(COALESCE(v_actor_profile.full_name, 'DESCONOCIDO')),
        'resolution', UPPER(trim(p_resolution_notes)),
        'timestamp', now()
    );
END;
$$;


ALTER FUNCTION "public"."fn_release_asset_lockout"("p_asset_id" "uuid", "p_resolution_notes" "text", "p_fitter_pin" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_request_detach"("p_reason" character varying) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$ 
BEGIN 
  UPDATE public.shift_assignments 
  SET intent_to_detach = true, detach_reason = p_reason 
  WHERE driver_id = auth.uid() AND status = 'ACTIVE'; 
END; 
$$;


ALTER FUNCTION "public"."fn_request_detach"("p_reason" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_request_detach"("p_shift_id" "uuid", "p_reason" character varying) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE public.shift_assignments 
  SET intent_to_detach = true, detach_reason = p_reason
  WHERE id = p_shift_id AND driver_id = auth.uid() AND status = 'ACTIVE';
END;
$$;


ALTER FUNCTION "public"."fn_request_detach"("p_shift_id" "uuid", "p_reason" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_revoke_driver_access"("p_driver_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_active_loads INT;
BEGIN
    -- Validar permisos del solicitante
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role IN ('FLEET_MANAGER', 'SUPER_ADMIN')
    ) THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE';
    END IF;

    -- Bloqueo Forense: Comprobar si el conductor tiene cargas en tránsito
    SELECT COUNT(id) INTO v_active_loads
    FROM public.load_offers
    WHERE driver_id = p_driver_id 
    AND status IN ('PENDING', 'LOADING', 'IN_TRANSIT', 'AT_WEIGHBRIDGE');

    IF v_active_loads > 0 THEN
        -- El error exacto que la UI debe atrapar
        RAISE EXCEPTION 'ACTIVE_TRANSIT_LOCK';
    END IF;

    -- Ejecutar Baja Definitiva
    UPDATE public.profiles
    SET status = 'INACTIVE'
    WHERE id = p_driver_id;

    RETURN true;
END;
$$;


ALTER FUNCTION "public"."fn_revoke_driver_access"("p_driver_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_revoke_user_role"("p_target_id" "uuid", "p_new_role" "text", "p_justification" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_executor_role TEXT;
    v_aal_level TEXT;
    v_previous_role TEXT;
BEGIN
    -- 3.1 Aserción Criptográfica de Hardware (AAL2) extraída directamente del JWT activo
    v_aal_level := current_setting('request.jwt.claims', true)::jsonb ->> 'aal';
    IF v_aal_level IS DISTINCT FROM 'aal2' THEN
        RAISE EXCEPTION 'AAL2 Required: MFA Hardware verification is strictly required for this operation.';
    END IF;

    -- 3.2 Validación Estricta de Identidad Ejecutora (Debe ser super_admin)
    SELECT role INTO v_executor_role FROM public.profiles WHERE id = auth.uid();
    IF v_executor_role IS DISTINCT FROM 'super_admin' THEN
        RAISE EXCEPTION 'Access Denied: Only a Super Admin can revoke roles.';
    END IF;

    -- 3.3 Validación de roles degradados permitidos ('driver' como base segura)
    IF p_new_role NOT IN ('driver', 'suspended') THEN
        RAISE EXCEPTION 'Invalid Role: Revocation target role must be driver or suspended.';
    END IF;

    -- 3.4 Obtener el rol actual
    SELECT role INTO v_previous_role FROM public.profiles WHERE id = p_target_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target user profile not found.';
    END IF;

    -- 3.5 Ejecutar la degradación en la capa operativa
    UPDATE public.profiles
    SET role = p_new_role
    WHERE id = p_target_id;

    -- 3.6 DESTRUCCIÓN FÍSICA DE LA RED (Aniquilar sesiones activas del usuario)
    -- Al borrar el token de la tabla auth.sessions y auth.refresh_tokens, el JWT del objetivo será
    -- invalidado en la próxima validación de la red, expulsándolo de inmediato de su Kiosco/Tablet.
    DELETE FROM auth.sessions WHERE user_id = p_target_id;
    DELETE FROM auth.refresh_tokens WHERE user_id = p_target_id;
    DELETE FROM auth.mfa_amr_claims WHERE session_id IN (SELECT id FROM auth.sessions WHERE user_id = p_target_id);

    -- 3.7 Sellar la auditoría forense
    INSERT INTO public.role_audit_logs (
        target_user_id, granted_by_user_id, previous_role, new_role, action_type, justification
    ) VALUES (
        p_target_id, auth.uid(), v_previous_role, p_new_role, 'REVOCATION', p_justification
    );

    RETURN 'SUCCESS: Role revoked and active sessions physically destroyed.';
END;
$$;


ALTER FUNCTION "public"."fn_revoke_user_role"("p_target_id" "uuid", "p_new_role" "text", "p_justification" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_set_operator_pin"("p_pin" character varying) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth', 'extensions'
    AS $_$
DECLARE
    v_caller_uid UUID;
    v_current_fleet UUID;
BEGIN
    v_caller_uid := auth.uid();

    -- ADUANA 0: Autenticación activa requerida
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: No se detectó una sesión AAL2 activa en el terminal.'
            USING ERRCODE = '40100';
    END IF;

    -- ADUANA 1: Validación de sintaxis estricta (Exactamente 4 dígitos numéricos)
    IF p_pin !~ '^[0-9]{4}$' THEN
        RAISE EXCEPTION 'INVALID_PIN_FORMAT: El PIN operativo debe constar estrictamente de 4 dígitos numéricos.'
            USING ERRCODE = '22023';
    END IF;

    -- ADUANA 2: Verificar que el operador ya pertenece a una flota (consumió su token 74BEAF)
    SELECT fleet_id INTO v_current_fleet FROM public.profiles WHERE id = v_caller_uid;
    IF v_current_fleet IS NULL THEN
        RAISE EXCEPTION 'JURISDICTION_MISSING: No puede configurar un PIN sin haber sido vinculado a una flota minera previamente.'
            USING ERRCODE = '42501';
    END IF;

    -- TRANSACCIÓN ATÓMICA A: Generar hash bcrypt con coste 8 y guardar en la columna oculta
    UPDATE public.profiles
    SET pin_hash = crypt(p_pin, gen_salt('bf', 8)),
        updated_at = now()
    WHERE id = v_caller_uid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'PROFILE_NOT_FOUND: El perfil biométrico del operador no existe en la base de datos.'
            USING ERRCODE = 'P0002';
    END IF;

    -- TRANSACCIÓN ATÓMICA B: Asentar el cambio de credenciales en el libro mayor inmutable
    INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
    VALUES (
        NULL,
        'PIN MILITAR OPERATIVO CONFIGURADO Y SELLADO CRIPTOGRÁFICAMENTE PARA UID: ' || v_caller_uid,
        v_caller_uid,
        'closed'
    );

    RETURN jsonb_build_object(
        'success', true,
        'operator_uid', v_caller_uid,
        'fleet_id', v_current_fleet,
        'security_level', 'BCRYPT_SALTED',
        'timestamp', now()
    );
END;
$_$;


ALTER FUNCTION "public"."fn_set_operator_pin"("p_pin" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_simulate_payment_success"("p_fleet_id" "uuid", "p_amount_due" numeric) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_actor_role TEXT;
    v_receipt_id VARCHAR(100);
BEGIN
    -- Determinar rol
    SELECT LOWER(role::text) INTO v_actor_role FROM public.profiles WHERE id = auth.uid();

    -- Escudo Zero-Trust estricto: El super_admin de la plataforma (tú) NUNCA debe
    -- pagar las deudas operativas de sus clientes. Solo el fleet_manager dueño de 
    -- la flota tiene jurisdicción financiera.
    IF v_actor_role <> 'fleet_manager' THEN
        RAISE EXCEPTION 'UNAUTHORIZED_ROLE: Solo el Fleet Manager autorizado puede liquidar deudas operativas.';
    END IF;

    -- Generar un ID forense simulando el formato estándar de Stripe
    v_receipt_id := 'ch_sim_' || encode(gen_random_bytes(12), 'hex');

    -- Transacción Atómica 1: Registrar el ingreso en el libro mayor
    INSERT INTO public.billing_ledger (fleet_id, amount_aud, stripe_charge_id, executed_by_uid)
    VALUES (p_fleet_id, p_amount_due, v_receipt_id, auth.uid());

    -- Transacción Atómica 2: Descongelar la flota
    UPDATE public.fleets
    SET status = 'active',
        updated_at = now()
    WHERE id = p_fleet_id AND LOWER(status::text) IN ('past_due', 'canceled', 'frozen');

    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_VIOLATION: La flota no existe o no requiere descongelamiento financiero.';
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'fleet_id', p_fleet_id,
        'new_status', 'active',
        'receipt_id', v_receipt_id,
        'timestamp', now()
    );
END;
$$;


ALTER FUNCTION "public"."fn_simulate_payment_success"("p_fleet_id" "uuid", "p_amount_due" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_snapshot_daily_billing"("p_target_date" "date" DEFAULT (("now"() AT TIME ZONE 'Australia/Hobart'::"text"))::"date") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_rows_upserted INT;
BEGIN
    INSERT INTO public.fleet_billing_ledger (
        fleet_id,
        project_site_id,
        billing_date,
        active_asset_count,
        billing_mode
    )
    SELECT 
        p.fleet_id,
        p.id AS project_site_id,
        p_target_date,
        COUNT(DISTINCT v.asset_id)::int AS active_asset_count,
        'SHADOW'
    FROM public.project_sites p
    LEFT JOIN public.vw_daily_billable_assets v 
        ON v.project_site_id = p.id AND v.operational_date = p_target_date
    WHERE p.status = 'ACTIVE' AND p.vault_status = 'OPERATIONAL'
    GROUP BY p.fleet_id, p.id
    ON CONFLICT (project_site_id, billing_date) 
    DO UPDATE SET 
        active_asset_count = EXCLUDED.active_asset_count,
        created_at = NOW();

    GET DIAGNOSTICS v_rows_upserted = ROW_COUNT;
    RETURN v_rows_upserted;
END;
$$;


ALTER FUNCTION "public"."fn_snapshot_daily_billing"("p_target_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_submit_fuel_log"("p_asset_id" "uuid", "p_liters_filled" numeric, "p_engine_hours" numeric, "p_cost_per_liter" numeric DEFAULT 1.85, "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_caller_uid UUID;
    v_profile RECORD;
    v_asset RECORD;
    v_last_fill RECORD;
    v_active_shift UUID;
    v_hours_elapsed NUMERIC(6,1);
    v_burn_rate NUMERIC(6,2);
    v_cycles_count INT := 0;
    v_tonnage_sum NUMERIC(8,2) := 0.00;
    v_status VARCHAR(30) := 'VERIFIED';
    v_now TIMESTAMPTZ := now();
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Terminal carece de sesión AAL2 válida.' USING ERRCODE = '40100';
    END IF;

    SELECT fleet_id, role INTO v_profile FROM public.profiles WHERE id = v_caller_uid;
    IF NOT FOUND OR v_profile.fleet_id IS NULL THEN
        RAISE EXCEPTION 'JURISDICTION_MISSING: Operario no vinculado a una flota.' USING ERRCODE = '42501';
    END IF;

    -- Bloqueo pesimista del activo para evitar recargas concurrentes (Double-Billing)
    SELECT id, fleet_id, baseline_burn_rate_lph, current_engine_hours 
    INTO v_asset FROM public.assets WHERE id = p_asset_id FOR UPDATE;

    IF NOT FOUND OR v_asset.fleet_id != v_profile.fleet_id THEN
        RAISE EXCEPTION 'ASSET_VIOLATION: Maquinaria ajena a su jurisdicción.' USING ERRCODE = '42501';
    END IF;

    -- ADUANA DE FÍSICA TEMPORAL: El horómetro nuevo NUNCA puede ser menor al actual
    IF p_engine_hours < v_asset.current_engine_hours THEN
        RAISE EXCEPTION 'ODOMETER_TAMPERING: Las horas-motor introducidas (%.1f) son inferiores al último registro oficial del servidor (%.1f).', p_engine_hours, v_asset.current_engine_hours
            USING ERRCODE = '22023';
    END IF;

    -- Extraer el último repostaje para calcular el delta temporal
    SELECT engine_hours_at_fill, created_at INTO v_last_fill 
    FROM public.fuel_logs WHERE asset_id = p_asset_id ORDER BY created_at DESC LIMIT 1;

    IF FOUND THEN
        v_hours_elapsed := p_engine_hours - v_last_fill.engine_hours_at_fill;
        
        -- TRIANGULACIÓN CON CONDUCTO 2: ¿Cuántos viajes y toneladas movió desde la última recarga?
        SELECT COUNT(*), COALESCE(SUM(tonnage_moved), 0.00)
        INTO v_cycles_count, v_tonnage_sum
        FROM public.haul_cycles
        WHERE asset_id = p_asset_id 
          AND state = 'COMPLETED' 
          AND completed_at >= v_last_fill.created_at;
    ELSE
        -- Primer repostaje registrado en la historia del camión dentro de JITSite
        v_hours_elapsed := GREATEST(1.0, p_engine_hours - v_asset.current_engine_hours);
    END IF;

    -- Evitar división por cero si recargan dos veces seguidas con el motor apagado
    IF v_hours_elapsed <= 0 THEN
        v_burn_rate := p_liters_filled; -- Tasa punitiva artificial para disparar anomalía
    ELSE
        v_burn_rate := p_liters_filled / v_hours_elapsed;
    END IF;

    -- =========================================================================
    -- MOTOR ALGORÍTMICO DE DETECCIÓN DE ANOMALÍAS Y ROBO EN TERRENO
    -- =========================================================================
    
    -- REGLA A: Sospecha de sifón / robo (Cargó más de 50L pero el motor no sumó horas o no hizo viajes)
    IF v_hours_elapsed <= 0.2 AND p_liters_filled > 50.00 THEN
        v_status := 'THEFT_SUSPECTED';
    
    -- REGLA B: Consumo excesivo / fuga grave (Quema 25% más del límite OEM del fabricante)
    ELSIF v_burn_rate > (v_asset.baseline_burn_rate_lph * 1.25) THEN
        v_status := 'ANOMALY_HIGH_BURN';
        
    -- REGLA C: Ralentí abusivo (Sumó más de 3 horas motor quemando combustible pero movió 0 toneladas)
    ELSIF v_hours_elapsed >= 3.0 AND v_tonnage_sum = 0.00 AND p_liters_filled > 40.00 THEN
        v_status := 'ANOMALY_IDLE_BURN';
    END IF;

    -- Identificar si hay un turno activo en esa cabina
    SELECT id INTO v_active_shift FROM public.shift_logs 
    WHERE operator_uid = v_caller_uid AND status = 'ACTIVE' ORDER BY started_at DESC LIMIT 1;

    -- TRANSACCIÓN ATÓMICA A: Insertar en el libro mayor de combustible
    INSERT INTO public.fuel_logs (
        fleet_id, asset_id, operator_uid, shift_id,
        liters_filled, cost_per_liter, total_cost,
        engine_hours_at_fill, previous_engine_hours, hours_elapsed,
        burn_rate_lph, haul_cycles_since_last_fill, tonnage_moved_since_last_fill,
        status, notes
    ) VALUES (
        v_profile.fleet_id, p_asset_id, v_caller_uid, v_active_shift,
        p_liters_filled, p_cost_per_liter, (p_liters_filled * p_cost_per_liter),
        p_engine_hours, COALESCE(v_last_fill.engine_hours_at_fill, v_asset.current_engine_hours), v_hours_elapsed,
        v_burn_rate, v_cycles_count, v_tonnage_sum,
        v_status, UPPER(trim(p_notes))
    );

    -- TRANSACCIÓN ATÓMICA B: Actualizar el horómetro maestro en el activo
    UPDATE public.assets SET current_engine_hours = p_engine_hours, updated_at = v_now WHERE id = p_asset_id;

    -- TRANSACCIÓN ATÓMICA C: Si hay anomalía forense, disparar sirena en el libro de mantenimiento
    IF v_status != 'VERIFIED' THEN
        INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
        VALUES (
            p_asset_id,
            '🚨 ALERTA FUELFLOW [' || v_status || ']: INYECTADOS ' || p_liters_filled || 'L. TASA: ' || ROUND(v_burn_rate, 1) || ' L/H (OEM: ' || v_asset.baseline_burn_rate_lph || ' L/H). TRABAJO: ' || v_tonnage_sum || 't EN ' || v_cycles_count || ' VIAJES.',
            v_caller_uid,
            'open'
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'status', v_status,
        'liters_filled', p_liters_filled,
        'total_cost', (p_liters_filled * p_cost_per_liter),
        'burn_rate_lph', ROUND(v_burn_rate, 2),
        'hours_elapsed', v_hours_elapsed,
        'tonnage_cross_ref', v_tonnage_sum,
        'timestamp', v_now
    );
END;
$$;


ALTER FUNCTION "public"."fn_submit_fuel_log"("p_asset_id" "uuid", "p_liters_filled" numeric, "p_engine_hours" numeric, "p_cost_per_liter" numeric, "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_submit_fuel_log"("p_asset_id" "uuid", "p_liters_filled" numeric, "p_engine_hours" numeric, "p_cost_per_liter" numeric DEFAULT 1.85, "p_location_tag" character varying DEFAULT 'PIT_STATION'::character varying) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_caller_uid UUID;
    v_caller_fleet UUID;
    v_asset RECORD;
    v_last_log RECORD;
    v_status VARCHAR(50) := 'VERIFIED';
    v_hours_elapsed NUMERIC := 0;
    v_burn_rate NUMERIC := 0;
    v_tonnage NUMERIC := 0;
    v_now TIMESTAMPTZ := now();
    v_cost NUMERIC;
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN RAISE EXCEPTION 'SESIÓN FANTASMA: Petición anónima bloqueada por Zero-Trust.' USING ERRCODE = '28000'; END IF;

    SELECT fleet_id INTO v_caller_fleet FROM public.profiles WHERE id = v_caller_uid;

    -- Bloqueo atómico del activo
    SELECT * INTO v_asset FROM public.assets WHERE id = p_asset_id FOR UPDATE;
    IF v_asset IS NULL THEN RAISE EXCEPTION 'ACTIVO INVÁLIDO' USING ERRCODE = '22023'; END IF;
    IF v_asset.fleet_id != v_caller_fleet THEN RAISE EXCEPTION 'JURISDICCIÓN DENEGADA' USING ERRCODE = '42501'; END IF;

    -- Evitar viaje en el tiempo del horómetro
    IF p_engine_hours < COALESCE(v_asset.current_engine_hours, 0) THEN
        RAISE EXCEPTION 'ODOMETER_TAMPERING: Las horas (%s) no pueden ser menores al registro actual (%s).', p_engine_hours, v_asset.current_engine_hours
            USING ERRCODE = '22003';
    END IF;

    -- Buscar último repostaje de la máquina para cruzar datos
    SELECT * INTO v_last_log FROM public.fuel_logs 
    WHERE asset_id = p_asset_id ORDER BY created_at DESC LIMIT 1;

    -- Motor Forense de Triangulación
    v_hours_elapsed := p_engine_hours - COALESCE(v_last_log.engine_hours_at_fill, v_asset.current_engine_hours);
    v_cost := ROUND(p_liters_filled * p_cost_per_liter, 2);

    IF v_hours_elapsed > 0 THEN
        v_burn_rate := ROUND(p_liters_filled / v_hours_elapsed, 2);
        
        -- Cruzar con el tonelaje movido en ese intervalo temporal (Conducto 2)
        SELECT COALESCE(SUM(tonnage_moved), 0) INTO v_tonnage
        FROM public.haul_cycles
        WHERE asset_id = p_asset_id 
        AND created_at >= COALESCE(v_last_log.created_at, v_now - interval '1 year');

        -- Detección Algorítmica de Fraude y Rendimiento
        IF v_tonnage = 0 AND p_liters_filled > 50 THEN
            v_status := 'THEFT_SUSPECTED'; -- Se llenó el tanque pero el camión no movió tierra. Robo o sifón probable.
        ELSIF v_burn_rate > (v_asset.baseline_burn_rate_lph * 1.25) THEN
            v_status := 'ANOMALY_HIGH_BURN'; -- Supera la tolerancia mecánica del 25%
        ELSIF v_tonnage = 0 AND v_hours_elapsed > 2 THEN
            v_status := 'ANOMALY_IDLE_BURN'; -- El motor estuvo encendido sin producir. (Peligroso en la mina).
        END IF;
    ELSE
        -- No se movió el camión. Si inyectan mucho diésel, es fraude.
        IF p_liters_filled > 50 THEN v_status := 'THEFT_SUSPECTED'; END IF;
    END IF;

    -- Sellar el registro en el WORM Ledger
    INSERT INTO public.fuel_logs (asset_id, fleet_id, operator_uid, liters_filled, total_cost, burn_rate_lph, engine_hours_at_fill, tonnage_moved_since_last_fill, status)
    VALUES (p_asset_id, v_caller_fleet, v_caller_uid, p_liters_filled, v_cost, v_burn_rate, p_engine_hours, v_tonnage, v_status);

    -- Actualizar el estado de la máquina
    UPDATE public.assets SET current_engine_hours = p_engine_hours, updated_at = v_now WHERE id = p_asset_id;

    -- Alerta automática si hay anomalía grave
    IF v_status IN ('THEFT_SUSPECTED', 'ANOMALY_HIGH_BURN') THEN
        INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
        VALUES (
            p_asset_id, 
            'TELEMETRÍA CRÍTICA: ' || v_status || ' (' || p_liters_filled || 'L inyectados sin producción justificada)', 
            v_caller_uid, 
            'in_progress'
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'status', v_status,
        'liters_filled', p_liters_filled,
        'burn_rate_lph', v_burn_rate,
        'hours_elapsed', v_hours_elapsed,
        'tonnage_cross_ref', v_tonnage,
        'total_cost', v_cost,
        'timestamp', v_now
    );
END;
$$;


ALTER FUNCTION "public"."fn_submit_fuel_log"("p_asset_id" "uuid", "p_liters_filled" numeric, "p_engine_hours" numeric, "p_cost_per_liter" numeric, "p_location_tag" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_submit_whs_prestart"("p_asset_id" "uuid", "p_checklist_data" "jsonb", "p_defect_notes" "jsonb", "p_passed" boolean, "p_client_timestamp" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_caller_uid UUID;
    v_operator_profile RECORD;
    v_asset_fleet_id UUID;
    v_log_id UUID;
    v_critical_notes TEXT;
BEGIN
    v_caller_uid := auth.uid();

    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Terminal carece de sesión AAL2 válida.' USING ERRCODE = '40100';
    END IF;

    SELECT fleet_id, role, full_name INTO v_operator_profile FROM public.profiles WHERE id = v_caller_uid;
    IF v_operator_profile.fleet_id IS NULL THEN
        RAISE EXCEPTION 'JURISDICTION_MISSING' USING ERRCODE = '42501';
    END IF;

    SELECT fleet_id INTO v_asset_fleet_id FROM public.assets WHERE id = p_asset_id;
    IF v_asset_fleet_id != v_operator_profile.fleet_id THEN
        RAISE EXCEPTION 'CROSS_FLEET_VIOLATION' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.whs_prestart_logs (asset_id, operator_uid, fleet_id, checklist_data, defect_notes, passed, client_timestamp)
    VALUES (p_asset_id, v_caller_uid, v_operator_profile.fleet_id, p_checklist_data, COALESCE(p_defect_notes, '{}'::jsonb), p_passed, p_client_timestamp) 
    RETURNING id INTO v_log_id;

    IF p_passed = TRUE THEN
        -- 🚨 CORRECCIÓN: Usar 'operational' en vez de 'AVAILABLE' y 'maintenance' en vez de 'OUT_OF_SERVICE'
        UPDATE public.assets 
        SET last_prestart_at = now(), last_prestart_by_uid = v_caller_uid, status = 'operational', updated_at = now()
        WHERE id = p_asset_id AND status != 'maintenance';

        RETURN jsonb_build_object('success', true, 'action', 'PRESTART_APPROVED', 'log_id', v_log_id, 'asset_status', 'operational', 'timestamp', now());
    ELSE
        SELECT string_agg(key || ': ' || value, ' | ') INTO v_critical_notes FROM jsonb_each_text(p_defect_notes);

        -- 🚨 CORRECCIÓN: Usar 'maintenance' en vez de 'OUT_OF_SERVICE'
        UPDATE public.assets SET status = 'maintenance', updated_at = now() WHERE id = p_asset_id;

        INSERT INTO public.asset_lockouts (asset_id, fleet_id, locked_by_operator_uid, prestart_log_id, lockout_reason, status) 
        VALUES (p_asset_id, v_operator_profile.fleet_id, v_caller_uid, v_log_id, COALESCE(v_critical_notes, 'FALLO CRÍTICO'), 'ACTIVE');

        INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status) 
        VALUES (p_asset_id, '🛑 ENCLAVAMIENTO WHS POR OPERARIO. DEFECTOS: ' || COALESCE(v_critical_notes, 'Ver bitácora ' || v_log_id), v_caller_uid, 'open');

        RETURN jsonb_build_object('success', true, 'action', 'FATAL_DEFECT_LOCKED', 'log_id', v_log_id, 'asset_status', 'maintenance', 'lockout_reason', v_critical_notes, 'timestamp', now());
    END IF;
END;
$$;


ALTER FUNCTION "public"."fn_submit_whs_prestart"("p_asset_id" "uuid", "p_checklist_data" "jsonb", "p_defect_notes" "jsonb", "p_passed" boolean, "p_client_timestamp" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_sweep_orphan_evidence"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    -- Delete objects in the docket_evidence bucket older than 48 hours
    -- that do not have a matching path in the load_offers table.
    -- (storage.objects.name contains the file path e.g. "offer_id/file.jpg")
    WITH deleted AS (
        DELETE FROM storage.objects
        WHERE bucket_id = 'docket_evidence'
          AND created_at < NOW() - INTERVAL '48 hours'
          AND name NOT IN (
              SELECT docket_image_path 
              FROM public.load_offers 
              WHERE docket_image_path IS NOT NULL
          )
        RETURNING id
    )
    SELECT count(*) INTO deleted_count FROM deleted;

    RAISE NOTICE 'Orphan Evidence Sweeper executed. Deleted % orphaned files.', deleted_count;
END;
$$;


ALTER FUNCTION "public"."fn_sweep_orphan_evidence"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_trigger_autoloop"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_shift_assignment RECORD;
  v_master_order RECORD;
  v_total_delivered NUMERIC;
  v_is_completed_transition BOOLEAN := false;
BEGIN
  -- Determine if this is a valid completion transition
  IF TG_OP = 'INSERT' THEN
      v_is_completed_transition := (NEW.status = 'COMPLETED');
  ELSIF TG_OP = 'UPDATE' THEN
      v_is_completed_transition := (NEW.status = 'COMPLETED' AND OLD.status != 'COMPLETED');
  END IF;

  IF v_is_completed_transition THEN
    
    -- Si la oferta pertenece a un Master Order
    IF NEW.master_order_id IS NOT NULL THEN
      
      -- Obtener detalles del Master Order
      SELECT * INTO v_master_order FROM public.master_orders WHERE id = NEW.master_order_id;
      
      IF FOUND THEN
        -- Calcular tonelaje entregado total para esta orden
        SELECT COALESCE(SUM(COALESCE(ocr_mass_extracted, loaded_gross_mass)), 0) INTO v_total_delivered 
        FROM public.load_offers 
        WHERE master_order_id = NEW.master_order_id AND status = 'COMPLETED';

        -- Si no se ha alcanzado la meta, generar el siguiente ciclo
        IF v_total_delivered < v_master_order.target_tonnage THEN
          -- Solo insertar si no existe ya una orden PENDING para este conductor en este Master Order.
          IF NOT EXISTS (SELECT 1 FROM public.load_offers WHERE driver_id = NEW.driver_id AND master_order_id = NEW.master_order_id AND status = 'PENDING') THEN
            INSERT INTO public.load_offers (
              master_order_id,
              driver_id,
              status,
              material_type,
              requires_4x4_traction,
              max_turn_radius_m,
              created_at
            ) VALUES (
              v_master_order.id,
              NEW.driver_id,
              'PENDING',
              v_master_order.material_type,
              v_master_order.requires_4x4_traction,
              v_master_order.max_turn_radius_m,
              NOW()
            );
          END IF;
        ELSE
          -- Cerrar el Master Order y los Turnos
          UPDATE public.master_orders SET status = 'FULFILLED' WHERE id = v_master_order.id;
          UPDATE public.shift_assignments SET status = 'COMPLETED' WHERE master_order_id = v_master_order.id;
        END IF;
      END IF;
    END IF;
  END IF;

  -- Romper el bucle si hay avería
  IF TG_OP = 'UPDATE' THEN
    IF NEW.status = 'BREAKDOWN' THEN
      UPDATE public.shift_assignments SET status = 'SUSPENDED_BREAKDOWN' WHERE driver_id = NEW.driver_id AND status = 'ACTIVE';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_trigger_autoloop"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_verify_driver_insurance"("p_driver_id" "uuid", "p_expiry_date" "date", "p_file_path" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_role VARCHAR;
BEGIN
    SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();
    IF v_role NOT IN ('supervisor', 'fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'UNAUTHORIZED_WHS_OVERRIDE: You do not have the required authority level.';
    END IF;

    INSERT INTO public.whs_overrides (supervisor_id, driver_id, document_path, new_expiry_date, override_timestamp)
    VALUES (auth.uid(), p_driver_id, p_file_path, p_expiry_date, now());

    UPDATE public.profiles
    SET insurance_expiry_date = p_expiry_date
    WHERE id = p_driver_id;

    RETURN true;
END;
$$;


ALTER FUNCTION "public"."fn_verify_driver_insurance"("p_driver_id" "uuid", "p_expiry_date" "date", "p_file_path" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_verify_operator_pin"("p_pin" character varying) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
    v_caller_uid UUID;
    v_profile RECORD;
    v_lockout_duration INTERVAL;
    v_attempts_left INT;
BEGIN
    v_caller_uid := auth.uid();

    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: No hay sesión activa en la terminal.' USING ERRCODE = '40100';
    END IF;

    -- Bloqueo FOR UPDATE para evitar que scripts asíncronos evadan el contador enviando 50 peticiones simultáneas
    SELECT pin_hash, pin_failed_attempts, pin_locked_until, full_name 
    INTO v_profile 
    FROM public.profiles 
    WHERE id = v_caller_uid 
    FOR UPDATE;

    IF NOT FOUND OR v_profile.pin_hash IS NULL THEN
        RAISE EXCEPTION 'PIN_NOT_SET: El operario no ha sellado su PIN militar aún.' USING ERRCODE = '42501';
    END IF;

    -- ADUANA 1: Evaluar si el cronómetro de exclusión sigue activo
    IF v_profile.pin_locked_until IS NOT NULL AND v_profile.pin_locked_until > now() THEN
        RETURN jsonb_build_object(
            'success', false,
            'status', 'LOCKED_OUT',
            'locked_until', v_profile.pin_locked_until,
            'seconds_remaining', EXTRACT(EPOCH FROM (v_profile.pin_locked_until - now()))::INT,
            'msg', 'Terminal temporalmente congelada por múltiples intentos fallidos.'
        );
    END IF;

    -- ADUANA 2: Verificación criptográfica (bcrypt Blowfish)
    IF v_profile.pin_hash = crypt(p_pin, v_profile.pin_hash) THEN
        -- ÉXITO: Limpiamos el historial de fallos y liberamos el acceso
        UPDATE public.profiles 
        SET pin_failed_attempts = 0, 
            pin_locked_until = NULL,
            updated_at = now() 
        WHERE id = v_caller_uid;

        RETURN jsonb_build_object(
            'success', true,
            'status', 'AUTHORIZED',
            'operator_uid', v_caller_uid,
            'timestamp', now()
        );
    END IF;

    -- FALLO CRIPTOGRÁFICO: Incrementamos el contador de infracciones
    v_profile.pin_failed_attempts := v_profile.pin_failed_attempts + 1;
    v_attempts_left := GREATEST(0, 3 - v_profile.pin_failed_attempts);

    -- Cálculo del Retroceso Geométrico:
    -- Intento 3 fallido = 60 segundos (1 min)
    -- Intento 4 fallido = 300 segundos (5 min)
    -- Intento 5+ fallido = 900 segundos (15 min) + Sirena de Ciberseguridad
    IF v_profile.pin_failed_attempts >= 3 THEN
        IF v_profile.pin_failed_attempts = 3 THEN
            v_lockout_duration := interval '1 minute';
        ELSIF v_profile.pin_failed_attempts = 4 THEN
            v_lockout_duration := interval '5 minutes';
        ELSE
            v_lockout_duration := interval '15 minutes';
            
            -- Disparo forense al libro mayor al alcanzar el umbral crítico
            INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
            VALUES (
                NULL, 
                'ALERTA DE SEGURIDAD WHS: FUERZA BRUTA DETECTADA EN TERMINAL PARA UID ' || v_caller_uid || '. BLOQUEO DE 15 MINUTOS APLICADO.', 
                v_caller_uid, 
                'closed'
            );
        END IF;

        UPDATE public.profiles 
        SET pin_failed_attempts = v_profile.pin_failed_attempts,
            pin_locked_until = now() + v_lockout_duration,
            updated_at = now() 
        WHERE id = v_caller_uid;

        RETURN jsonb_build_object(
            'success', false,
            'status', 'LOCKED_OUT',
            'locked_until', now() + v_lockout_duration,
            'seconds_remaining', EXTRACT(EPOCH FROM v_lockout_duration)::INT,
            'msg', 'Umbral de seguridad excedido. Sistema en retroceso geométrico.'
        );
    ELSE
        -- Aún le quedan intentos antes de activar la exclusión
        UPDATE public.profiles 
        SET pin_failed_attempts = v_profile.pin_failed_attempts,
            updated_at = now() 
        WHERE id = v_caller_uid;

        RETURN jsonb_build_object(
            'success', false,
            'status', 'INVALID_PIN',
            'attempts_left', v_attempts_left,
            'msg', 'PIN incorrecto. Le quedan ' || v_attempts_left || ' intentos antes del bloqueo operativo.'
        );
    END IF;
END;
$$;


ALTER FUNCTION "public"."fn_verify_operator_pin"("p_pin" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."force_close_shift"("p_assignment_id" "uuid", "p_reason" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_caller_id UUID;
    v_fleet_id UUID;
BEGIN
    -- 1. Extraer la identidad absoluta del JWT
    v_caller_id := auth.uid();
    
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_UNAUTHORIZED: Identidad criptográfica ausente. Terminación denegada.';
    END IF;

    -- 2. Ejecutar la terminación táctica del activo
    UPDATE public.asset_assignments
    SET 
        shift_end = now(),
        status = 'completed',
        -- Reutilizamos las columnas de excepción para estampar la auditoría del cierre forzado
        fatigue_override_reason = COALESCE(fatigue_override_reason, '') || ' [FORCED CLOSURE: ' || p_reason || ']',
        override_approved_by = v_caller_id
    WHERE id = p_assignment_id 
      AND shift_end IS NULL; -- Solo afecta a turnos abiertos (infinitos)

    -- 3. Validar el impacto de la operación
    IF NOT FOUND THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_INVALID_TARGET: El turno no existe, pertenece a otra flota, o ya fue cerrado forensemente.';
    END IF;
END;
$$;


ALTER FUNCTION "public"."force_close_shift"("p_assignment_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_execution_certificate"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_contract RECORD;
    v_total_hours NUMERIC(8, 2);
    v_regular_hours NUMERIC(8, 2);
    v_overtime_hours NUMERIC(8, 2);
    v_asset_subtotal NUMERIC(12, 2);
    v_operator_subtotal NUMERIC(12, 2);
    
    -- Variables de telemetría IoT
    v_start_engine_hours NUMERIC(10, 2);
    v_end_engine_hours NUMERIC(10, 2);
    v_iot_delta_hours NUMERIC(8, 2);
    
    -- Metadatos de confianza
    v_source VARCHAR(50) := 'tablet_gps_time';
    v_confidence NUMERIC(3, 2) := 0.50;
BEGIN
    IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        
        SELECT * INTO v_contract 
        FROM public.billing_contracts 
        WHERE asset_id = NEW.asset_id AND is_active = true;
        
        IF NOT FOUND THEN
            RETURN NEW;
        END IF;

        -- 1. Intento de Conciliación IoT (Buscar lectura en el inicio y en el fin)
        SELECT engine_hours INTO v_start_engine_hours 
        FROM public.telemetry_logs 
        WHERE asset_id = NEW.asset_id AND recorded_at >= NEW.prestart_commenced_at 
        ORDER BY recorded_at ASC LIMIT 1;

        SELECT engine_hours INTO v_end_engine_hours 
        FROM public.telemetry_logs 
        WHERE asset_id = NEW.asset_id AND recorded_at <= NEW.shift_end 
        ORDER BY recorded_at DESC LIMIT 1;

        -- 2. Matriz de Fallback (IoT vs Humano)
        IF v_start_engine_hours IS NOT NULL AND v_end_engine_hours IS NOT NULL AND (v_end_engine_hours >= v_start_engine_hours) THEN
            -- Tenemos datos duros del CAN bus. El hardware manda.
            v_iot_delta_hours := v_end_engine_hours - v_start_engine_hours;
            v_total_hours := v_iot_delta_hours;
            v_source := 'iot_can_bus';
            v_confidence := 1.00;
        ELSE
            -- FALLBACK: El activo no tiene hardware IoT o falló la transmisión. 
            -- Se degrada la confianza y se cobra por el tiempo físico del operador.
            v_total_hours := ROUND((EXTRACT(EPOCH FROM (NEW.shift_end - NEW.prestart_commenced_at)) / 3600.0)::numeric, 2);
            v_iot_delta_hours := NULL;
            v_source := 'tablet_gps_time';
            v_confidence := 0.50;
        END IF;

        IF v_total_hours < 0 THEN v_total_hours := 0; END IF;

        -- 3. Cálculo de Fatiga y WHS (Se mantiene idéntico)
        IF v_total_hours > v_contract.overtime_threshold_hours THEN
            v_regular_hours := v_contract.overtime_threshold_hours;
            v_overtime_hours := v_total_hours - v_contract.overtime_threshold_hours;
        ELSE
            v_regular_hours := v_total_hours;
            v_overtime_hours := 0;
        END IF;

        v_asset_subtotal := v_total_hours * v_contract.hourly_rate_asset;

        IF v_contract.model = 'wet_hire' THEN
            v_operator_subtotal := (v_regular_hours * v_contract.hourly_rate_operator) +
                                   (v_overtime_hours * (v_contract.hourly_rate_operator * v_contract.overtime_multiplier));
        ELSE
            v_operator_subtotal := 0;
        END IF;

        -- 4. Inyección en el Libro Mayor con sellos de auditoría
        INSERT INTO public.execution_certificates (
            assignment_id, contract_id, total_hours, regular_hours, overtime_hours,
            asset_subtotal, operator_subtotal, total_billable,
            telemetry_source, telemetry_confidence, hardware_engine_hours
        ) VALUES (
            NEW.id, v_contract.id, v_total_hours, v_regular_hours, v_overtime_hours,
            v_asset_subtotal, v_operator_subtotal, (v_asset_subtotal + v_operator_subtotal),
            v_source, v_confidence, v_iot_delta_hours
        );
        
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."generate_execution_certificate"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_admin_business_metrics"() RETURNS TABLE("active_users" bigint, "active_projects" bigint, "projected_mrr" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF (SELECT role FROM profiles WHERE id = auth.uid()) != 'super_admin' THEN
        RAISE EXCEPTION 'Access Denied: Super Admin privileges required.';
    END IF;

    RETURN QUERY
    SELECT
        (SELECT COUNT(DISTINCT id) FROM profiles)::BIGINT AS active_users,
        (SELECT COUNT(DISTINCT id) FROM projects WHERE status = 'active')::BIGINT AS active_projects,
        (SELECT COALESCE(SUM(CASE WHEN project_type = 'long_term' THEN 500 ELSE 1500 END), 0) FROM projects)::BIGINT AS projected_mrr;
END;
$$;


ALTER FUNCTION "public"."get_admin_business_metrics"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_auth_user_fleet_id"() RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  SELECT fleet_id FROM public.profiles WHERE id = auth.uid();
$$;


ALTER FUNCTION "public"."get_auth_user_fleet_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_auth_user_role"() RETURNS "text"
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  SELECT role::text FROM public.profiles WHERE id = auth.uid();
$$;


ALTER FUNCTION "public"."get_auth_user_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_fleet_friction_metrics"("p_fleet_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_total_assets INT;
    v_assets_in_maintenance INT;
    v_total_cash_burn NUMERIC;
    v_fatigued_operators INT;
    v_result JSONB;
BEGIN
    -- 1. Estado de la Flota
    SELECT count(*) INTO v_total_assets FROM public.assets WHERE fleet_id = p_fleet_id;
    SELECT count(*) INTO v_assets_in_maintenance FROM public.assets WHERE fleet_id = p_fleet_id AND status = 'maintenance';

    -- 2. Quema de Efectivo Diaria (Máquinas asignadas pero no facturando / estancadas en pending_prestart)
    -- Calculamos el lucro cesante asumiendo que un camión en pending_prestart pierde el hourly_rate_asset
    SELECT COALESCE(SUM(
        EXTRACT(EPOCH FROM (now() - aa.created_at)) / 3600.0 * bc.hourly_rate_asset
    ), 0) INTO v_total_cash_burn
    FROM public.asset_assignments aa
    JOIN public.assets a ON aa.asset_id = a.id
    JOIN public.billing_contracts bc ON a.id = bc.asset_id
    WHERE a.fleet_id = p_fleet_id 
      AND aa.status = 'pending_prestart'
      AND bc.is_active = true
      AND aa.created_at >= current_date;

    -- 3. Densidad de Fatiga WHS (Operadores al borde del límite de 10h)
    SELECT count(DISTINCT driver_id) INTO v_fatigued_operators
    FROM public.asset_assignments aa
    JOIN public.assets a ON aa.asset_id = a.id
    WHERE a.fleet_id = p_fleet_id
      AND aa.created_at >= current_date
      AND (EXTRACT(EPOCH FROM (COALESCE(aa.shift_end, now()) - aa.created_at)) / 3600.0) >= 10.0;

    v_result := jsonb_build_object(
        'fleet_readiness_percent', CASE WHEN v_total_assets > 0 THEN ROUND(((v_total_assets - v_assets_in_maintenance)::numeric / v_total_assets) * 100, 1) ELSE 0 END,
        'active_maintenance_locks', v_assets_in_maintenance,
        'daily_idle_cash_burn_aud', ROUND(v_total_cash_burn, 2),
        'critical_fatigue_operators', v_fatigued_operators,
        'timestamp', now()
    );

    RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."get_fleet_friction_metrics"("p_fleet_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."access_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "table_name" character varying(100) NOT NULL,
    "row_id" "uuid" NOT NULL,
    "action" character varying(20) NOT NULL,
    "timestamp" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."access_logs" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_offer_chronology"("offer_uuid" "uuid") RETURNS SETOF "public"."access_logs"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT al.* 
    FROM access_logs al
    WHERE 
        (al.table_name = 'load_offers' AND al.row_id = offer_uuid)
        OR 
        (al.table_name = 'cor_manifests' AND al.row_id IN (
            SELECT id FROM cor_manifests WHERE load_offer_id = offer_uuid
        ))
        OR 
        (al.table_name = 'structural_elements' AND al.row_id IN (
            SELECT id FROM structural_elements WHERE load_offer_id = offer_uuid
        ))
    ORDER BY al.timestamp DESC;
END;
$$;


ALTER FUNCTION "public"."get_offer_chronology"("offer_uuid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    v_role VARCHAR(50);
    v_fleet_id UUID;
    v_fleet_name TEXT;
BEGIN
    -- Extraer metadatos enviados desde el formulario de registro de React
    v_role := COALESCE(NEW.raw_user_meta_data->>'role', 'pending_onboarding');
    v_fleet_name := NEW.raw_user_meta_data->>'fleet_name';

    -- Si intentan registrarse como account_owner sin pasar por Stripe, los degradamos al limbo
    IF v_role = 'account_owner' THEN
        v_role := 'pending_onboarding';
    END IF;

    -- Si existe una invitación formal (empleado), le respetamos su flota y rol asignado
    IF NEW.raw_user_meta_data->>'invited_fleet_id' IS NOT NULL THEN
        v_fleet_id := (NEW.raw_user_meta_data->>'invited_fleet_id')::uuid;
        v_role := COALESCE(NEW.raw_user_meta_data->>'invited_role', 'driver');
    END IF;

    INSERT INTO public.profiles (
        id, full_name, role, fleet_id, created_at
    ) VALUES (
        NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', 'Usuario Minero'),
        v_role, v_fleet_id, NOW()
    );
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "fleet_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "role" character varying(50) NOT NULL,
    "full_name" character varying(255),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "insurance_policy_number" character varying(100),
    "insurance_expiry_date" "date",
    "is_verified" boolean DEFAULT false,
    "status" character varying(20) DEFAULT 'ACTIVE'::character varying,
    "operational_pin_hash" "text",
    "operational_pin_salt" "text",
    "hashed_pin" "text",
    "pin_hash" "text",
    "pin_failed_attempts" integer DEFAULT 0,
    "pin_locked_until" timestamp with time zone,
    "expires_at" timestamp with time zone,
    CONSTRAINT "chk_profiles_fleet_id_not_null" CHECK (((("role")::"text" = ANY ((ARRAY['pending_onboarding'::character varying, 'super_admin'::character varying])::"text"[])) OR ("fleet_id" IS NOT NULL))),
    CONSTRAINT "profiles_role_check" CHECK ((("role")::"text" = ANY ((ARRAY['super_admin'::character varying, 'fleet_manager'::character varying, 'fitter'::character varying, 'driver'::character varying, 'account_owner'::character varying, 'pending_onboarding'::character varying, 'dispatcher'::character varying, 'supervisor'::character varying, 'suspended'::character varying])::"text"[])))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."insurance_compliant"("public"."profiles") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $_$
  SELECT $1.insurance_expiry_date > CURRENT_DATE;
$_$;


ALTER FUNCTION "public"."insurance_compliant"("public"."profiles") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."join_jit_queue"("p_asset_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_project_id UUID;
    v_asset_status VARCHAR;
    v_asset_category VARCHAR;
BEGIN
    SELECT current_project_id, status, asset_type INTO v_project_id, v_asset_status, v_asset_category
    FROM assets WHERE id = p_asset_id;

    IF v_project_id IS NULL OR v_asset_category != 'haul_truck' THEN
        RETURN;
    END IF;

    -- Solo insertamos si el camión está activo y no tiene defectos críticos
    INSERT INTO jit_active_queues (project_id, asset_id, status) 
    VALUES (v_project_id, p_asset_id, 'waiting') 
    ON CONFLICT (project_id, asset_id, status) DO NOTHING;
END;
$$;


ALTER FUNCTION "public"."join_jit_queue"("p_asset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."leave_jit_queue"("p_asset_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_project_id UUID;
    v_project_name TEXT;
    v_excavator_status VARCHAR;
    v_active_material TEXT;
    v_active_block TEXT;
    v_closest_truck_id UUID;
    v_truck RECORD;
    v_shift_start TIMESTAMPTZ;
    v_driver_id UUID;
    v_driver_name TEXT;
    v_asset_code TEXT;
    v_shift_duration_hours NUMERIC;
BEGIN
    SELECT a.current_project_id, p.name INTO v_project_id, v_project_name
    FROM assets a
    LEFT JOIN projects p ON p.id = a.current_project_id
    WHERE a.id = p_asset_id;

    IF v_project_id IS NULL THEN RETURN; END IF;

    -- Purge del camión saliente
    DELETE FROM jit_active_queues WHERE asset_id = p_asset_id;
    UPDATE load_cycles SET status = 'in_transit', transit_started_at = CURRENT_TIMESTAMP 
    WHERE asset_id = p_asset_id AND status = 'loading';

    -- Evaluar si se debe despachar al siguiente camión
    SELECT operational_status, current_material, geological_block INTO v_excavator_status, v_active_material, v_active_block
    FROM excavator_states 
    WHERE asset_id = (SELECT id FROM assets WHERE current_project_id = v_project_id AND asset_type = 'excavator' LIMIT 1);

    IF v_excavator_status IS NULL THEN v_excavator_status := 'ready_to_load'; END IF;
    IF v_active_material IS NULL THEN v_active_material := 'Unclassified Excavation'; END IF;

    IF v_excavator_status != 'ready_to_load' THEN RETURN; END IF;

    v_closest_truck_id := NULL;
    FOR v_truck IN SELECT asset_id FROM jit_active_queues WHERE project_id = v_project_id AND status = 'waiting' ORDER BY joined_queue_at ASC LOOP
        SELECT created_at, driver_id INTO v_shift_start, v_driver_id FROM shift_assignments WHERE vehicle_id = v_truck.asset_id AND status = 'ACTIVE' ORDER BY created_at DESC LIMIT 1;
        IF v_shift_start IS NULL THEN v_shift_start := CURRENT_TIMESTAMP; END IF;

        v_shift_duration_hours := EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_shift_start)) / 3600.0;
        
        IF v_shift_duration_hours >= 11.5 THEN
            SELECT a.asset_code, COALESCE(pr.full_name, 'Usuario Desconocido') INTO v_asset_code, v_driver_name
            FROM assets a LEFT JOIN profiles pr ON pr.id = v_driver_id WHERE a.id = v_truck.asset_id;
            
            INSERT INTO webhook_events (event_type, payload)
            VALUES ('compliance_violation', jsonb_build_object(
                'project_id', v_project_id, 'project_name', v_project_name,
                'asset_id', v_truck.asset_id, 'asset_code', v_asset_code,
                'driver_name', v_driver_name, 'shift_duration_hours', ROUND(v_shift_duration_hours::numeric, 2),
                'legal_limit_hours', 11.5, 'timestamp', CURRENT_TIMESTAMP,
                'alert_type', 'compliance_violation',
                'message', format('ALERTA CoR: Operador %s ha sido expulsado de la cola JIT en el activo %s. Tiempo de conducción actual: %s horas (Límite NHVR: 11.5h). Detenga la máquina de forma segura.', v_driver_name, v_asset_code, ROUND(v_shift_duration_hours::numeric, 2))
            ));
            CONTINUE;
        ELSE
            v_closest_truck_id := v_truck.asset_id;
            EXIT;
        END IF;
    END LOOP;

    IF v_closest_truck_id IS NOT NULL THEN
        UPDATE jit_active_queues SET status = 'dispatched' WHERE asset_id = v_closest_truck_id;
        INSERT INTO load_cycles (project_id, asset_id, status, material_type, geological_block, loading_started_at) 
        VALUES (v_project_id, v_closest_truck_id, 'loading', v_active_material, v_active_block, CURRENT_TIMESTAMP);
        PERFORM pg_notify('pgrst', jsonb_build_object('table', 'assets', 'action', 'broadcast', 'channel', 'jit_dispatch_' || v_closest_truck_id::TEXT, 'payload', jsonb_build_object('message', 'Atención. Proceda al cargadero principal de inmediato. Excavadora libre.'))::TEXT);
        INSERT INTO webhook_events (event_type, payload) VALUES ('jit_dispatch', jsonb_build_object('project_id', v_project_id, 'asset_id', v_closest_truck_id));
    END IF;
END;
$$;


ALTER FUNCTION "public"."leave_jit_queue"("p_asset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lock_asset_preventively"("p_asset_id" "uuid", "p_reason" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_actor_role TEXT;
BEGIN
    v_actor_role := current_setting('request.jwt.claims', true)::jsonb ->> 'user_role';

    -- Escudo Jurisdiccional: Solo mecánicos y gerentes pueden interceptar
    IF v_actor_role NOT IN ('fitter', 'fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'WHS_UNAUTHORIZED: Solo el personal de taller puede ordenar un secuestro preventivo.';
    END IF;

    -- Transacción Atómica: Cambia el estado del activo (bloqueando nuevos Pre-Starts)
    -- y deja un registro en la bitácora forense.
    UPDATE public.assets
    SET status = 'maintenance'
    WHERE id = p_asset_id AND status = 'available';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_VIOLATION: El activo ya está secuestrado o no existe.';
    END IF;

    INSERT INTO public.maintenance_logs (asset_id, issue_description, locked_by_uid, status)
    VALUES (p_asset_id, '[PREDICTIVO] ' || p_reason, auth.uid(), 'open');
END;
$$;


ALTER FUNCTION "public"."lock_asset_preventively"("p_asset_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_infrastructure_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_actor_id UUID;
    v_actor_role TEXT;
BEGIN
    -- Extraer contexto de seguridad del JWT actual
    v_actor_id := auth.uid();
    v_actor_role := current_setting('request.jwt.claims', true)::jsonb ->> 'user_role';

    IF (TG_OP = 'UPDATE') THEN
        INSERT INTO public.system_audit_logs (
            actor_uid, actor_role, action_type, target_table, target_record_id, 
            payload_before, payload_after
        ) VALUES (
            v_actor_id,
            v_actor_role,
            TG_OP || '_' || TG_TABLE_NAME,
            TG_TABLE_NAME,
            NEW.id,
            to_jsonb(OLD),
            to_jsonb(NEW)
        );
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO public.system_audit_logs (
            actor_uid, actor_role, action_type, target_table, target_record_id, 
            payload_before, payload_after
        ) VALUES (
            v_actor_id,
            v_actor_role,
            TG_OP || '_' || TG_TABLE_NAME,
            TG_TABLE_NAME,
            OLD.id,
            to_jsonb(OLD),
            NULL
        );
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO public.system_audit_logs (
            actor_uid, actor_role, action_type, target_table, target_record_id, 
            payload_before, payload_after
        ) VALUES (
            v_actor_id,
            v_actor_role,
            TG_OP || '_' || TG_TABLE_NAME,
            TG_TABLE_NAME,
            NEW.id,
            NULL,
            to_jsonb(NEW)
        );
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."log_infrastructure_mutation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_prestart_commenced"("p_assignment_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_caller_id UUID;
    v_record RECORD;
BEGIN
    v_caller_id := auth.uid();
    
    SELECT * INTO v_record FROM public.asset_assignments WHERE id = p_assignment_id FOR UPDATE;
    
    -- Validar jurisdicción
    IF v_record.driver_id != v_caller_id THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_UNAUTHORIZED: Solo el operador asignado puede iniciar la inspección.';
    END IF;
    
    -- Solo marcar si no ha sido marcado previamente (resiliencia ante recargas de página)
    IF v_record.prestart_commenced_at IS NULL THEN
        UPDATE public.asset_assignments 
        SET prestart_commenced_at = now() 
        WHERE id = p_assignment_id;
    END IF;
END;
$$;


ALTER FUNCTION "public"."mark_prestart_commenced"("p_assignment_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."matches_contractor_profile"("driver_uuid" "uuid", "offer_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    driver_asset_4x4 BOOLEAN;
    driver_asset_radius DECIMAL(4,2);
    offer_requires_4x4 BOOLEAN;
    offer_max_radius DECIMAL(4,2);
BEGIN
    -- Obtenemos el vehículo activo asignado al driver
    SELECT has_4x4_traction, turning_radius_m INTO driver_asset_4x4, driver_asset_radius
    FROM assets WHERE driver_id = driver_uuid AND is_active = true LIMIT 1;

    -- Obtenemos los requisitos de la oferta
    SELECT requires_4x4_traction, max_turn_radius_m INTO offer_requires_4x4, offer_max_radius
    FROM load_offers WHERE id = offer_id;

    -- Si el conductor no tiene un vehículo asignado, no ve ninguna oferta que tenga requisitos especiales
    IF driver_asset_4x4 IS NULL THEN
        driver_asset_4x4 := false;
    END IF;

    -- Evaluamos la física del vehículo contra la obra
    IF offer_requires_4x4 = true AND driver_asset_4x4 = false THEN
        RETURN false;
    END IF;

    IF offer_max_radius IS NOT NULL AND (driver_asset_radius IS NULL OR driver_asset_radius > offer_max_radius) THEN
        RETURN false;
    END IF;

    RETURN true;
END;
$$;


ALTER FUNCTION "public"."matches_contractor_profile"("driver_uuid" "uuid", "offer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."matchmaker_dispatch_on_excavator_ready"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_project_id UUID;
    v_project_name TEXT;
    v_active_material TEXT;
    v_active_block TEXT;
    v_closest_truck_id UUID;
    v_truck RECORD;
    v_shift_start TIMESTAMPTZ;
    v_driver_id UUID;
    v_driver_name TEXT;
    v_asset_code TEXT;
    v_shift_duration_hours NUMERIC;
BEGIN
    IF NEW.operational_status != 'ready_to_load' OR (OLD.operational_status = 'ready_to_load') THEN
        RETURN NEW;
    END IF;

    SELECT current_project_id INTO v_project_id FROM assets WHERE id = NEW.asset_id;
    IF v_project_id IS NULL THEN RETURN NEW; END IF;
    
    SELECT name INTO v_project_name FROM projects WHERE id = v_project_id;
    v_active_material := NEW.current_material;
    v_active_block := NEW.geological_block;

    v_closest_truck_id := NULL;
    FOR v_truck IN SELECT asset_id FROM jit_active_queues WHERE project_id = v_project_id AND status = 'waiting' ORDER BY joined_queue_at ASC LOOP
        SELECT created_at, driver_id INTO v_shift_start, v_driver_id FROM shift_assignments WHERE vehicle_id = v_truck.asset_id AND status = 'ACTIVE' ORDER BY created_at DESC LIMIT 1;
        IF v_shift_start IS NULL THEN v_shift_start := CURRENT_TIMESTAMP; END IF;

        v_shift_duration_hours := EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_shift_start)) / 3600.0;
        
        IF v_shift_duration_hours >= 11.5 THEN
            SELECT a.asset_code, COALESCE(pr.full_name, 'Usuario Desconocido') INTO v_asset_code, v_driver_name
            FROM assets a LEFT JOIN profiles pr ON pr.id = v_driver_id WHERE a.id = v_truck.asset_id;
            
            INSERT INTO webhook_events (event_type, payload)
            VALUES ('compliance_violation', jsonb_build_object(
                'project_id', v_project_id, 'project_name', v_project_name,
                'asset_id', v_truck.asset_id, 'asset_code', v_asset_code,
                'driver_name', v_driver_name, 'shift_duration_hours', ROUND(v_shift_duration_hours::numeric, 2),
                'legal_limit_hours', 11.5, 'timestamp', CURRENT_TIMESTAMP,
                'alert_type', 'compliance_violation',
                'message', format('ALERTA CoR: Operador %s ha sido expulsado de la cola JIT en el activo %s. Tiempo de conducción actual: %s horas (Límite NHVR: 11.5h). Detenga la máquina de forma segura.', v_driver_name, v_asset_code, ROUND(v_shift_duration_hours::numeric, 2))
            ));
            CONTINUE;
        ELSE
            v_closest_truck_id := v_truck.asset_id;
            EXIT;
        END IF;
    END LOOP;

    IF v_closest_truck_id IS NOT NULL THEN
        UPDATE jit_active_queues SET status = 'dispatched' WHERE asset_id = v_closest_truck_id;
        INSERT INTO load_cycles (project_id, asset_id, status, material_type, geological_block, loading_started_at) 
        VALUES (v_project_id, v_closest_truck_id, 'loading', v_active_material, v_active_block, CURRENT_TIMESTAMP);
        PERFORM pg_notify('pgrst', jsonb_build_object('table', 'assets', 'action', 'broadcast', 'channel', 'jit_dispatch_' || v_closest_truck_id::TEXT, 'payload', jsonb_build_object('message', 'Atención. Proceda al cargadero principal de inmediato. Excavadora libre.'))::TEXT);
        INSERT INTO webhook_events (event_type, payload) VALUES ('jit_dispatch', jsonb_build_object('project_id', v_project_id, 'asset_id', v_closest_truck_id));
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."matchmaker_dispatch_on_excavator_ready"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_edge_function_on_certificate"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_edge_function_url TEXT := current_setting('app.settings.webhook_edge_url', true);
    v_payload JSONB;
    v_request_id BIGINT;
BEGIN
    IF v_edge_function_url IS NULL OR v_edge_function_url = '' THEN
        RETURN NEW;
    END IF;

    -- Construir el payload referencial para la Edge Function
    v_payload := jsonb_build_object(
        'event_type', 'billing.certificate.generated',
        'record_id', NEW.id,
        'assignment_id', NEW.assignment_id,
        'total_billable', NEW.total_billable,
        'generated_at', NEW.generated_at
    );

    -- Disparar y olvidar (Fire-and-Forget) mediante pg_net
    SELECT net.http_post(
        url := v_edge_function_url,
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := v_payload
    ) INTO v_request_id;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."notify_edge_function_on_certificate"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_edge_function_on_critical_audit"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_edge_function_url TEXT := current_setting('app.settings.webhook_edge_url', true);
    v_payload JSONB;
    v_request_id BIGINT;
BEGIN
    IF v_edge_function_url IS NULL OR v_edge_function_url = '' THEN
        RETURN NEW;
    END IF;

    -- Filtro de Severidad: Solo emitimos alertas hacia fuera si el cambio afecta el dinero
    IF NEW.target_table NOT IN ('billing_contracts') THEN
        RETURN NEW;
    END IF;

    -- Construir el payload referencial
    v_payload := jsonb_build_object(
        'event_type', 'audit.infrastructure.breach',
        'record_id', NEW.id,
        'target_table', NEW.target_table
    );

    -- Disparar y olvidar (Fire-and-Forget)
    SELECT net.http_post(
        url := v_edge_function_url,
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := v_payload
    ) INTO v_request_id;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."notify_edge_function_on_critical_audit"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_edge_function_on_lock"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    -- La URL de tu Edge Function se define en los secretos/variables de entorno de PostgreSQL
    v_edge_function_url TEXT := current_setting('app.settings.webhook_edge_url', true);
    v_payload JSONB;
    v_request_id BIGINT;
BEGIN
    -- Mecanismo de seguridad: Si la URL no está configurada, abortar el envío silenciosamente 
    -- para jamás bloquear la transacción WHS del mecánico.
    IF v_edge_function_url IS NULL OR v_edge_function_url = '' THEN
        RETURN NEW;
    END IF;

    -- Construir un payload estrictamente referencial. 
    -- No enviamos todo el log, solo las coordenadas para que Deno haga el trabajo pesado.
    v_payload := jsonb_build_object(
        'event_type', 'asset.locked.critical',
        'record_id', NEW.id,
        'asset_id', NEW.asset_id,
        'locked_at', NEW.locked_at
    );

    -- Disparar y olvidar: net.http_post es asíncrono y no bloquea el COMMIT de la base de datos.
    SELECT net.http_post(
        url := v_edge_function_url,
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := v_payload
    ) INTO v_request_id;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."notify_edge_function_on_lock"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."process_handover_signature"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_pin TEXT;
    v_operator_id UUID;
    v_pin_hash TEXT;
    v_is_valid BOOLEAN;
BEGIN
    -- Solo interceptar eventos handover_signature
    IF NEW.event_type = 'handover_signature' THEN
        -- Extraer el PIN plano que viene en la telemetría (Blind Queue)
        v_pin := NEW.payload->>'pin';
        v_operator_id := NEW.recorded_by;
        
        -- Si no trae pin, es una aserción fraudulenta instantánea
        IF v_pin IS NULL THEN
            UPDATE assets SET status = 'out_of_service' WHERE id = NEW.asset_id;
            PERFORM net.http_post(
                url:='https://n8n.fuelflow.com/webhook/handover-fraud',
                body:=json_build_object('asset_id', NEW.asset_id, 'operator_id', v_operator_id, 'reason', 'missing_pin')::jsonb
            );
            NEW.payload := NEW.payload - 'pin';
            RETURN NEW;
        END IF;

        -- Buscar el hash real del operador en la base de datos central
        SELECT pin_hash INTO v_pin_hash
        FROM profiles
        WHERE id = v_operator_id;
        
        -- Validar matemáticamente usando pgcrypto
        v_is_valid := (v_pin_hash = crypt(v_pin, v_pin_hash));

        -- Si la firma criptográfica es falsa, disparar RED TAG y alerta forense
        IF NOT v_is_valid THEN
            -- Inyectar Red Tag al activo
            UPDATE assets SET status = 'out_of_service' WHERE id = NEW.asset_id;
            
            -- Disparar webhook a n8n para alertar a la gerencia
            PERFORM net.http_post(
                url:='https://n8n.fuelflow.com/webhook/handover-fraud',
                body:=json_build_object('asset_id', NEW.asset_id, 'operator_id', v_operator_id, 'reason', 'invalid_pin')::jsonb
            );
        END IF;
        
        -- Amnesia de base de datos: Borrar el PIN plano del JSON antes de guardarlo en disco (Data at Rest)
        NEW.payload := NEW.payload - 'pin';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."process_handover_signature"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."process_quarantined_expense"("p_expense_id" "uuid", "p_status" character varying, "p_corrected_amount" numeric, "p_notes" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_actor_role TEXT;
    v_expense RECORD;
BEGIN
    v_actor_role := current_setting('request.jwt.claims', true)::jsonb ->> 'user_role';

    -- Escudo Jurisdiccional
    IF v_actor_role NOT IN ('supervisor', 'fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'WHS_UNAUTHORIZED: Solo los supervisores tácticos pueden auditar gastos análogos.';
    END IF;

    -- Extraer el gasto
    SELECT * INTO v_expense FROM public.expense_quarantine WHERE id = p_expense_id FOR UPDATE;

    IF NOT FOUND OR v_expense.status != 'pending_review' THEN
        RAISE EXCEPTION 'STATE_VIOLATION: El gasto ya fue procesado o no existe en la cuarentena.';
    END IF;

    -- Actualizar estado
    UPDATE public.expense_quarantine
    SET status = p_status,
        reviewed_by_uid = auth.uid(),
        review_notes = p_notes,
        updated_at = now()
    WHERE id = p_expense_id;

    -- Inyección directa al Outbox como un evento separado
    IF p_status = 'approved' THEN
        INSERT INTO public.erp_outbox (id, certificate_id, payload)
        VALUES (
            gen_random_uuid(),
            NULL,
            jsonb_build_object(
                'event', 'billing.expense.approved',
                'expense_id', p_expense_id,
                'shift_id', v_expense.shift_id,
                'category', v_expense.expense_category,
                'approved_amount', p_corrected_amount,
                'auditor_uid', auth.uid(),
                'timestamp', now()
            )
        );
    END IF;
END;
$$;


ALTER FUNCTION "public"."process_quarantined_expense"("p_expense_id" "uuid", "p_status" character varying, "p_corrected_amount" numeric, "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."process_telemetry_safety_override"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Si la temperatura supera los 105°C, la máquina entra en modo de alerta crítica
    IF NEW.coolant_temp_celsius >= 105.00 THEN
        -- 1. Inyectar un registro de mantenimiento automático por falla crítica
        INSERT INTO public.maintenance_logs (
            asset_id, locked_by_uid, issue_description
        ) VALUES (
            NEW.asset_id, 
            NULL, -- SYSTEM BOT / TELEMETRY OVERRIDE
            '[AUTOMATED IOT LOCK] CRITICAL ENGINE OVERHEAT DETECTED: ' || NEW.coolant_temp_celsius || '°C'
        );
        
        -- 2. Cambiar el estado del activo
        UPDATE public.assets 
        SET status = 'maintenance' 
        WHERE id = NEW.asset_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."process_telemetry_safety_override"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."process_webhook_responses"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    r RECORD;
    v_new_request_id BIGINT;
    v_backoff_minutes INT;
BEGIN
    -- Barrer eventos despachados cuyo tiempo de reintento haya expirado (Batch Limit 50)
    FOR r IN 
        SELECT we.*, nr.status_code, nr.error_msg, nr.id as response_id
        FROM webhook_events we
        LEFT JOIN net.http_response nr ON we.request_id = nr.id
        WHERE we.status = 'dispatched_to_pgnet'
          AND (we.next_retry_at IS NULL OR we.next_retry_at <= now())
        ORDER BY we.created_at ASC
        LIMIT 50
    LOOP
        -- Si aún no hay respuesta de pg_net, continuar (está en vuelo)
        IF r.response_id IS NULL AND r.request_id IS NOT NULL THEN
            CONTINUE;
        END IF;

        -- Evaluar éxito
        IF r.status_code >= 200 AND r.status_code < 300 THEN
            UPDATE webhook_events 
            SET status = 'delivered', error_message = NULL 
            WHERE id = r.id;
        ELSE
            -- Fallo o Timeout de Red
            -- max_retries innegociable establecido en 5
            IF r.retry_count >= 5 THEN
                -- Arrojar a la Cola de la Muerte (DLQ)
                INSERT INTO dead_letter_queue (original_event_id, event_type, payload, last_error)
                VALUES (r.id, r.event_type, r.payload, COALESCE(r.error_msg, 'HTTP ' || r.status_code::text));
                
                UPDATE webhook_events 
                SET status = 'failed', error_message = COALESCE(r.error_msg, 'Exhausted retries. HTTP ' || r.status_code::text)
                WHERE id = r.id;
            ELSE
                -- Retroceso Progresivo Prolongado (1m, 5m, 15m, 30m, 60m)
                v_backoff_minutes := CASE 
                    WHEN r.retry_count = 0 THEN 1
                    WHEN r.retry_count = 1 THEN 5
                    WHEN r.retry_count = 2 THEN 15
                    WHEN r.retry_count = 3 THEN 30
                    WHEN r.retry_count = 4 THEN 60
                    ELSE 60
                END;

                -- Reinyectar el webhook
                SELECT net.http_post(
                    url := 'https://n8n.fuelflow.example.com/webhook/fuelflow-events',
                    body := jsonb_build_object(
                        'event_id', r.id,
                        'event_type', r.event_type,
                        'payload', r.payload,
                        'created_at', r.created_at
                    ),
                    headers := jsonb_build_object(
                        'Content-Type', 'application/json',
                        'x-idempotency-key', r.id::text
                    ),
                    timeout_milliseconds := 5000
                ) INTO v_new_request_id;

                UPDATE webhook_events 
                SET retry_count = r.retry_count + 1,
                    next_retry_at = now() + (v_backoff_minutes || ' minutes')::interval,
                    request_id = v_new_request_id,
                    error_message = COALESCE(r.error_msg, 'HTTP ' || r.status_code::text)
                WHERE id = r.id;
            END IF;
        END IF;
    END LOOP;
    
    -- Recolección de Basura Selectiva y Límite de Retención (30 días)
    -- 1. Purgar las peticiones HTTP que el orquestador confirmó exitosamente (delivered)
    DELETE FROM net.http_request 
    WHERE id IN (
        SELECT request_id FROM webhook_events WHERE status = 'delivered'
    );
    
    -- 2. Purgar absolutamente cualquier registro forense mayor a 30 días para evitar asfixia del disco
    DELETE FROM net.http_request WHERE created < (now() - interval '30 days');
    DELETE FROM dead_letter_queue WHERE failed_at < (now() - interval '30 days');
END;
$$;


ALTER FUNCTION "public"."process_webhook_responses"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."project_asset_telemetry_state"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    current_asset_timestamp TIMESTAMP WITH TIME ZONE;
BEGIN
    SELECT last_telemetry_timestamp INTO current_asset_timestamp
    FROM assets WHERE id = NEW.asset_id;

    IF NEW.client_timestamp > COALESCE(current_asset_timestamp, '1970-01-01'::timestamptz) THEN
        UPDATE assets
        SET
            status = COALESCE((NEW.payload->>'status'), status),
            last_odometer_checkin = COALESCE((NEW.payload->>'odometer')::NUMERIC, last_odometer_checkin),
            current_project_id = COALESCE((NEW.payload->>'project_id')::UUID, current_project_id),
            -- Nueva línea: Proyectar la ubicación si viene en el payload
            last_known_location = COALESCE((NEW.payload->'location'), last_known_location),
            last_telemetry_timestamp = NEW.client_timestamp
        WHERE id = NEW.asset_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."project_asset_telemetry_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."protect_contract_lifecycle"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Si el estado ya no es abierto, prohibir modificar elementos estructurales
  IF (SELECT status FROM load_offers WHERE id = NEW.load_offer_id) != 'BIDDING_OPEN' THEN
    RAISE EXCEPTION 'El contrato está bloqueado. No se pueden modificar elementos estructurales una vez iniciada la puja.';
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."protect_contract_lifecycle"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."protect_forensic_hash"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Si el hash ya existía y alguien intenta actualizarlo o borrarlo, la base de datos colapsa la transacción
    IF OLD.forensic_pdf_hash IS NOT NULL AND NEW.forensic_pdf_hash IS DISTINCT FROM OLD.forensic_pdf_hash THEN
        RAISE EXCEPTION 'TAMPER_ALERT: El hash forense del certificado es inmutable y no puede ser alterado ni siquiera por el superadministrador.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."protect_forensic_hash"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."push_to_n8n_webhook"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    -- URL de n8n orquestador
    v_n8n_webhook_url TEXT := 'https://n8n.fuelflow.example.com/webhook/fuelflow-events';
    v_request_body JSONB;
    v_request_id BIGINT;
BEGIN
    -- Riqueza del Payload: Firma Forense completa inyectada
    v_request_body := jsonb_build_object(
        'event_id', NEW.id,
        'event_type', NEW.event_type,
        'payload', NEW.payload,
        'created_at', NEW.created_at
    );

    -- Captura del Puntero y Timeouts Estrictos (5 segundos máximo)
    -- Inyección del encabezado x-idempotency-key para garantizar la unicidad del flujo
    SELECT net.http_post(
        url := v_n8n_webhook_url,
        body := v_request_body,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-idempotency-key', NEW.id::text
        ),
        timeout_milliseconds := 5000
    ) INTO v_request_id;

    -- Almacenar el request_id retornado y mutar el estado
    NEW.request_id := v_request_id;
    NEW.status := 'dispatched_to_pgnet';
    NEW.retry_count := 0;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."push_to_n8n_webhook"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."queue_erp_outbox"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    INSERT INTO public.erp_outbox (certificate_id, payload)
    VALUES (
        NEW.id,
        jsonb_build_object(
            'event', 'billing.certificate.generated',
            'certificate_id', NEW.id,
            'total_billable', NEW.total_billable,
            'total_hours', NEW.total_hours,
            'forensic_hash', NEW.forensic_pdf_hash,
            'client_xero_id', NEW.billed_to_erp_id, -- INYECCIÓN DIRECTA PARA N8N
            'timestamp', now()
        )
    );
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."queue_erp_outbox"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reconcile_load_cycle"("p_cycle_id" "uuid", "p_gross_weight" numeric, "p_tare_weight" numeric) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_cycle_record RECORD;
    v_operator_id UUID;
BEGIN
    -- Capturar la identidad del usuario que ejecuta la función
    v_operator_id := auth.uid();
    
    IF v_operator_id IS NULL THEN
        RAISE EXCEPTION 'Aduana: Se requiere autenticación criptográfica para facturar.';
    END IF;

    -- Bloqueo transaccional FOR UPDATE: 
    -- Evita que dos clics simultáneos procesen el mismo ciclo (Double-Spending)
    SELECT * INTO v_cycle_record 
    FROM load_cycles 
    WHERE id = p_cycle_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Aduana: El ticket de carga % no existe.', p_cycle_id;
    END IF;

    -- Validación estricta de la Máquina de Estados
    IF v_cycle_record.status != 'in_transit' THEN
        RAISE EXCEPTION 'Aduana: Rechazado. El ciclo está en estado % (Debe ser in_transit).', v_cycle_record.status;
    END IF;

    IF p_gross_weight <= p_tare_weight THEN
        RAISE EXCEPTION 'Aduana: Rechazado. El peso bruto debe ser mayor al peso tara.';
    END IF;

    -- Ejecutar el cierre financiero. 
    -- Nota: net_weight se autocalcula en la tabla (generated always as gross - tare)
    UPDATE load_cycles
    SET 
        status = 'reconciled',
        gross_weight = p_gross_weight,
        tare_weight = p_tare_weight,
        completed_at = CURRENT_TIMESTAMP,
        reconciled_by = v_operator_id
    WHERE id = p_cycle_id;

    -- Retornar el payload serializado para el Kiosk
    RETURN jsonb_build_object(
        'success', true,
        'cycle_id', p_cycle_id,
        'status', 'reconciled',
        'message', 'Ticket cerrado y conciliado exitosamente'
    );
END;
$$;


ALTER FUNCTION "public"."reconcile_load_cycle"("p_cycle_id" "uuid", "p_gross_weight" numeric, "p_tare_weight" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_managerial_kpis"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_cycle_efficiency;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_production_tonnage;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_fleet_downtime;
END;
$$;


ALTER FUNCTION "public"."refresh_managerial_kpis"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."release_asset_from_maintenance"("p_asset_id" "uuid", "p_release_notes" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_mechanic_uid UUID;
    v_log_id UUID;
    v_actor_role TEXT;
BEGIN
    v_mechanic_uid := auth.uid();
    v_actor_role := current_setting('request.jwt.claims', true)::jsonb ->> 'user_role';

    -- Fricción Forense 1: Solo personal de taller o super_admin puede liberar
    IF v_actor_role NOT IN ('fitter', 'fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'WHS_UNAUTHORIZED: Solo el personal certificado de taller puede firmar la liberación de un activo.';
    END IF;
    
    -- Fricción Forense 2: Justificación legal obligatoria
    IF length(trim(p_release_notes)) < 15 THEN
        RAISE EXCEPTION 'WHS_INVALID_RELEASE: Se requiere un informe pericial de reparación de al menos 15 caracteres.';
    END IF;

    -- Buscar el secuestro activo
    SELECT id INTO v_log_id
    FROM public.maintenance_logs
    WHERE asset_id = p_asset_id AND status = 'open'
    ORDER BY created_at DESC LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_VIOLATION: Este activo no posee bloqueos mecánicos activos.';
    END IF;

    -- Transacción Atómica: Cierre de bitácora y liberación del activo
    UPDATE public.maintenance_logs
    SET status = 'resolved',
        released_by_uid = v_mechanic_uid,
        resolution_notes = p_release_notes,
        released_at = now()
    WHERE id = v_log_id;

    UPDATE public.assets
    SET status = 'available'
    WHERE id = p_asset_id;
END;
$$;


ALTER FUNCTION "public"."release_asset_from_maintenance"("p_asset_id" "uuid", "p_release_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."report_incident"("p_offer_id" "uuid", "p_description" "text", "p_lat" numeric, "p_lng" numeric) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Verificar que la oferta está asignada a quien llama
  IF NOT EXISTS (
    SELECT 1 FROM public.assignments 
    WHERE load_offer_id = p_offer_id AND operator_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Solo el operador asignado puede reportar incidentes para esta carga.';
  END IF;

  INSERT INTO public.cor_incidents (load_offer_id, operator_id, description, gps_location)
  VALUES (
    p_offer_id,
    auth.uid(),
    p_description,
    point(p_lng, p_lat) -- Formato estándar de punto: (longitud, latitud)
  );
END;
$$;


ALTER FUNCTION "public"."report_incident"("p_offer_id" "uuid", "p_description" "text", "p_lat" numeric, "p_lng" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_plant_defect"("p_defect_id" "uuid", "p_category" "public"."defect_category", "p_resolution_notes" "text", "p_mechanic_pin" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_defect_record RECORD;
    v_mechanic_id UUID;
    v_mechanic_hash TEXT;
    v_asset_id UUID;
BEGIN
    -- Capturar identidad del mecánico
    v_mechanic_id := auth.uid();
    
    IF v_mechanic_id IS NULL THEN
        RAISE EXCEPTION 'Triaje: Se requiere autenticación criptográfica.';
    END IF;

    -- Extraer y validar el PIN del mecánico
    SELECT hashed_pin INTO v_mechanic_hash 
    FROM profiles 
    WHERE id = v_mechanic_id;

    IF v_mechanic_hash IS NULL THEN
        RAISE EXCEPTION 'Triaje: El usuario no tiene un PIN mecánico configurado.';
    END IF;

    -- Validación matemática (pgcrypto)
    IF v_mechanic_hash != crypt(p_mechanic_pin, v_mechanic_hash) THEN
        RAISE EXCEPTION 'Triaje: PIN criptográfico incorrecto. Fitter Override denegado.';
    END IF;

    -- Bloqueo transaccional FOR UPDATE sobre el defecto
    SELECT * INTO v_defect_record 
    FROM plant_defects 
    WHERE id = p_defect_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Triaje: El ticket de defecto % no existe.', p_defect_id;
    END IF;

    IF v_defect_record.status != 'reported' THEN
        RAISE EXCEPTION 'Triaje: El defecto ya no está activo (estado actual: %).', v_defect_record.status;
    END IF;

    v_asset_id := v_defect_record.asset_id;

    -- Ejecutar la Transición Dual Atómica
    
    -- 1. Cerrar el ticket de defecto
    UPDATE plant_defects
    SET 
        status = 'rectified',
        category = p_category,
        resolution_notes = p_resolution_notes,
        rectified_by = v_mechanic_id,
        rectified_at = CURRENT_TIMESTAMP
    WHERE id = p_defect_id;

    -- 2. NOTA: La tabla plant_defects ya tiene un TRIGGER (trg_sync_asset_status_on_defect)
    -- que se dispara AFTER UPDATE OF status y cambia el asset a 'active' o 'out_of_service'.
    -- Por lo tanto, no necesitamos hacer el UPDATE assets manual aquí, el motor transaccional
    -- lo orquesta de manera autónoma. Esto previene dobles responsabilidades en el código.

    -- 3. Emitir el webhook pasivo para notificación externa (n8n)
    INSERT INTO webhook_events (event_type, payload)
    VALUES (
        'plant_defect_rectified',
        jsonb_build_object(
            'defect_id', p_defect_id,
            'asset_id', v_asset_id,
            'mechanic_id', v_mechanic_id,
            'category', p_category,
            'notes', p_resolution_notes,
            'timestamp', CURRENT_TIMESTAMP
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'asset_id', v_asset_id,
        'message', 'Fitter Override exitoso. El hardware ha sido liberado.'
    );
END;
$$;


ALTER FUNCTION "public"."resolve_plant_defect"("p_defect_id" "uuid", "p_category" "public"."defect_category", "p_resolution_notes" "text", "p_mechanic_pin" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resurrect_dead_letter"("p_outbox_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_actor_role TEXT;
BEGIN
    v_actor_role := current_setting('request.jwt.claims', true)::jsonb ->> 'user_role';

    -- Fricción Criptográfica: Solo administradores de flota pueden forzar la contabilidad
    IF v_actor_role NOT IN ('fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'WHS_UNAUTHORIZED: Solo el gerente de flota puede resucitar registros financieros muertos.';
    END IF;

    -- Transacción Atómica: Resetear contadores y devolver a la cola
    UPDATE public.erp_outbox
    SET status = 'pending',
        retry_count = 0,
        next_retry_at = now(),
        last_error = '[RESURRECTED BY ' || auth.uid() || '] ' || COALESCE(last_error, '')
    WHERE id = p_outbox_id AND status = 'dead_letter';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'STATE_VIOLATION: El registro no existe o no está en estado dead_letter.';
    END IF;
END;
$$;


ALTER FUNCTION "public"."resurrect_dead_letter"("p_outbox_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."revoke_pending_shift"("p_assignment_id" "uuid", "p_reason" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_caller_id UUID;
    v_caller_role TEXT;
    v_status assignment_status;
BEGIN
    v_caller_id := auth.uid();
    -- Obtenemos el rol desde profiles
    SELECT role INTO v_caller_role FROM public.profiles WHERE id = v_caller_id;

    IF v_caller_role NOT IN ('supervisor', 'fleet_manager', 'super_admin') THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_UNAUTHORIZED: Solo el mando logístico puede revocar un despacho.';
    END IF;

    -- Bloqueo y verificación
    SELECT status INTO v_status 
    FROM public.asset_assignments 
    WHERE id = p_assignment_id FOR UPDATE;

    IF v_status != 'pending_prestart' THEN
        RAISE EXCEPTION 'P0001' USING MESSAGE = 'WHS_CONFLICT: Solo se pueden revocar turnos que nunca iniciaron la operación física.';
    END IF;

    -- Aniquilación del turno: Colapsamos el tiempo y estampamos la auditoría
    UPDATE public.asset_assignments
    SET 
        status = 'revoked',
        shift_end = now(),
        fatigue_override_reason = '[REVOKED ABANDONMENT] ' || COALESCE(p_reason, ''),
        override_approved_by = v_caller_id
    WHERE id = p_assignment_id;
END;
$$;


ALTER FUNCTION "public"."revoke_pending_shift"("p_assignment_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."seed_test_trip"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_offer_id UUID;
  v_uid UUID;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado.';
  END IF;

  -- Crear una oferta de carga en estado OPEN
  INSERT INTO public.load_offers (
    contractor_id, 
    crane_window_start, 
    crane_window_end, 
    destination_lat, 
    destination_lng, 
    requires_4x4_traction, 
    status
  )
  VALUES (
    v_uid, 
    now(), 
    now() + interval '4 hours', 
    -33.8688, 
    151.2093, 
    false, 
    'MANIFEST_PENDING' -- Para probar directamente el dashboard de ActiveTrip
  )
  RETURNING id INTO v_offer_id;

  -- Crear la asignación al conductor (él mismo, para testing rápido)
  INSERT INTO public.assignments (
    load_offer_id,
    operator_id
  )
  VALUES (
    v_offer_id,
    v_uid
  );
END;
$$;


ALTER FUNCTION "public"."seed_test_trip"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."simulate_docket_ocr"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  variance_threshold INT;
BEGIN
  -- Leer la tolerancia de la tabla de configuración
  SELECT (value::text)::int INTO variance_threshold 
  FROM system_config 
  WHERE key = 'ocr_mass_variance_threshold_kg';
  
  -- Fallback en caso de que la config no exista
  IF variance_threshold IS NULL THEN
    variance_threshold := 500;
  END IF;

  -- Si el conductor usa el Override de Emergencia, esto ya se seteó a DRIVER_EMERGENCY_OVERRIDE.
  -- No sobreescribimos si ya viene con anomalía de override.
  IF NEW.anomaly_flag = 'DRIVER_EMERGENCY_OVERRIDE' THEN
    RETURN NEW;
  END IF;

  -- Solo evaluar cuando se transiciona a IN_TRANSIT (salida)
  IF NEW.status = 'IN_TRANSIT' AND OLD.status != 'IN_TRANSIT' AND NEW.docket_image_path IS NOT NULL THEN
    
    -- Lógica Simulada: Si termina en 9, asumimos error o engaño detectado
    IF NEW.loaded_gross_mass % 10 = 9 THEN
      NEW.ocr_mass_extracted := NEW.loaded_gross_mass - variance_threshold;
      NEW.anomaly_flag := 'MASS_MISMATCH';
    ELSE
      -- Si es legal
      NEW.ocr_mass_extracted := NEW.loaded_gross_mass;
    END IF;
    
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."simulate_docket_ocr"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staging_area_geojson"("offer" "public"."load_offers") RETURNS "jsonb"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  SELECT ST_AsGeoJSON(offer.staging_area)::jsonb;
$$;


ALTER FUNCTION "public"."staging_area_geojson"("offer" "public"."load_offers") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_trip"("p_shipment_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Stub function to allow the UI to succeed
    NULL;
END;
$$;


ALTER FUNCTION "public"."start_trip"("p_shipment_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_telemetry_event"("p_asset_id" "uuid", "p_recorded_by" "uuid", "p_event_type" "text", "p_payload" "jsonb", "p_client_timestamp" timestamp with time zone) RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    -- Validar autenticación básica antes de procesar cualquier dato
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated';
    END IF;

    -- Intentar la inserción en el libro mayor inmutable
    INSERT INTO asset_telemetry_logs (
        asset_id,
        recorded_by,
        event_type,
        payload,
        client_timestamp
    ) VALUES (
        p_asset_id,
        p_recorded_by,
        p_event_type,
        p_payload,
        p_client_timestamp
    );

    RETURN 'SUCCESS';

EXCEPTION 
    -- Interceptar errores de integridad referencial, violaciones de checks o tipos malformados
    WHEN foreign_key_violation OR numeric_value_out_of_range OR check_violation OR data_exception THEN
        INSERT INTO telemetry_dead_letter_logs (
            asset_id,
            recorded_by,
            event_type,
            payload,
            client_timestamp,
            error_code,
            error_message
        ) VALUES (
            p_asset_id,
            p_recorded_by,
            p_event_type,
            p_payload,
            p_client_timestamp,
            SQLSTATE,
            SQLERRM
        );
        RETURN 'DEAD_LETTER_ROUTED';
    WHEN OTHERS THEN
        -- Errores inesperados de infraestructura crítica se relanzan para abortar
        RAISE;
END;
$$;


ALTER FUNCTION "public"."submit_telemetry_event"("p_asset_id" "uuid", "p_recorded_by" "uuid", "p_event_type" "text", "p_payload" "jsonb", "p_client_timestamp" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sweep_stagnant_queues"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_stagnant RECORD;
    v_project_name TEXT;
    v_asset_code TEXT;
    v_wait_time_minutes NUMERIC;
BEGIN
    FOR v_stagnant IN 
        SELECT q.id, q.project_id, q.asset_id, q.joined_queue_at 
        FROM jit_active_queues q
        WHERE q.status = 'waiting' 
          AND (CURRENT_TIMESTAMP - q.joined_queue_at) > interval '15 minutes'
          AND NOT EXISTS (
              SELECT 1 FROM webhook_events 
              WHERE event_type = 'logistic_bottleneck' 
                AND payload->>'asset_id' = q.asset_id::TEXT
                AND created_at > (CURRENT_TIMESTAMP - interval '1 hour')
          )
    LOOP
        v_wait_time_minutes := EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_stagnant.joined_queue_at)) / 60.0;
        
        SELECT p.name, a.asset_code 
        INTO v_project_name, v_asset_code
        FROM assets a
        JOIN projects p ON a.current_project_id = p.id
        WHERE a.id = v_stagnant.asset_id;

        -- Empujar alerta al sumidero para n8n con payload desnormalizado
        INSERT INTO webhook_events (event_type, payload)
        VALUES ('logistic_bottleneck', jsonb_build_object(
            'project_id', v_stagnant.project_id, 
            'project_name', v_project_name,
            'asset_id', v_stagnant.asset_id,
            'asset_code', v_asset_code,
            'waiting_minutes', ROUND(v_wait_time_minutes::numeric, 2),
            'threshold_minutes', 15,
            'timestamp', CURRENT_TIMESTAMP,
            'alert_type', 'logistic_bottleneck',
            'message', format('CUELLO DE BOTELLA: Vehículo %s inactivo en cargadero de %s superó umbral de 15 minutos (Lleva %s min).', v_asset_code, v_project_name, ROUND(v_wait_time_minutes::numeric, 2))
        ));
    END LOOP;
END;
$$;


ALTER FUNCTION "public"."sweep_stagnant_queues"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_asset_status_on_defect"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_project_name TEXT;
    v_asset_code TEXT;
    v_reporter_name TEXT;
    v_payload JSONB;
BEGIN
    IF NEW.status = 'reported' THEN
        -- Retirar el camión/excavadora del juego operativo inmediatamente
        UPDATE assets 
        SET status = 'out_of_service'
        WHERE id = NEW.asset_id;

        -- Evacuación Lógica de la Cola (Prevención de Cuello de Botella Fantasma)
        DELETE FROM jit_active_queues 
        WHERE asset_id = NEW.asset_id;
        
        -- Abortar ciclos de carga vulnerables
        -- Si estaba cargando o en tránsito, el material no llegará a la báscula de forma natural.
        UPDATE load_cycles 
        SET status = 'reconciled', 
            material_type = 'ABORTED_DEFECT',
            completed_at = CURRENT_TIMESTAMP
        WHERE asset_id = NEW.asset_id AND status IN ('loading', 'in_transit');

        -- Capturar datos literales en una sola operación indexada
        SELECT p.name, a.asset_code, COALESCE(pr.full_name, 'Usuario Desconocido')
        INTO v_project_name, v_asset_code, v_reporter_name
        FROM assets a
        JOIN projects p ON a.current_project_id = p.id
        LEFT JOIN profiles pr ON pr.id = NEW.reported_by
        WHERE a.id = NEW.asset_id;

        -- Construir el payload auto-contenido
        v_payload := jsonb_build_object(
            'project_id', NEW.project_id,
            'project_name', v_project_name,
            'asset_id', NEW.asset_id,
            'asset_code', v_asset_code,
            'reported_by_name', v_reporter_name,
            'defect_description', NEW.defect_description,
            'timestamp', NEW.reported_at,
            'alert_type', 'maintenance_critical',
            'message', format('CRITICAL: El activo %s ha sido inmovilizado por %s en %s debido a: %s. Requiere intervención inmediata del taller.', 
                              v_asset_code, v_reporter_name, v_project_name, NEW.defect_description)
        );

        -- Expulsar al Outbox
        INSERT INTO webhook_events (event_type, payload)
        VALUES ('maintenance_critical', v_payload);

    ELSIF NEW.status = 'rectified' AND OLD.status != 'rectified' THEN
        -- Restaurar el camión al estado limpio listo para operar
        UPDATE assets 
        SET status = 'available'
        WHERE id = NEW.asset_id;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_asset_status_on_defect"() OWNER TO "postgres";


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


CREATE OR REPLACE FUNCTION "public"."trg_validate_dispatch"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_req_license UUID;
    v_has_license BOOLEAN;
    v_total_hours NUMERIC;
    v_asset_status asset_status;
BEGIN
    -- A. Validar que el activo existe y está operativo
    SELECT required_license_id, status INTO v_req_license, v_asset_status
    FROM public.assets
    WHERE id = NEW.asset_id;

    IF v_asset_status != 'operational' THEN
        RAISE EXCEPTION 'WHS_ASSET_NOT_OPERATIONAL: Cannot assign an asset in % state.', v_asset_status;
    END IF;

    -- B. Validar Licencia del Conductor en tiempo real
    SELECT EXISTS (
        SELECT 1 FROM public.driver_licenses
        WHERE driver_id = NEW.driver_id
          AND license_category_id = v_req_license
          AND expiry_date >= CURRENT_DATE
    ) INTO v_has_license;

    IF NOT v_has_license THEN
        RAISE EXCEPTION 'WHS_INVALID_LICENSE: Driver lacks a valid unexpired license for this asset category.';
    END IF;

    -- C. Validación Dinámica de Fatiga (El Muro Permeable)
    -- Sumamos las horas de todos los turnos en las últimas 24 horas para este conductor
    SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (COALESCE(shift_end, now()) - shift_start)) / 3600), 0)
    INTO v_total_hours
    FROM public.asset_assignments
    WHERE driver_id = NEW.driver_id
      AND shift_start >= now() - INTERVAL '24 hours'
      AND status != 'revoked' -- NO CONTAR TURNOS REVOCADOS
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

    -- Límite WHS: 12 horas acumuladas.
    IF v_total_hours >= 12 THEN
        -- Si no hay justificación escrita, se aborta irrevocablemente la transacción
        IF NEW.fatigue_override_reason IS NULL OR TRIM(NEW.fatigue_override_reason) = '' THEN
            RAISE EXCEPTION 'WHS_FATIGUE_LIMIT: Driver accumulated % hours in 24h (>12h). Auditable override reason required.', ROUND(v_total_hours, 1);
        END IF;
        
        -- Si hay justificación, forzamos que quede sellada por quien aprueba
        IF NEW.override_approved_by IS NULL THEN
            NEW.override_approved_by := NEW.assigned_by;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_validate_dispatch"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_audit_compliance_doc"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- Registro automático en el historial forense
  INSERT INTO access_logs (user_id, table_name, row_id, action)
  VALUES (auth.uid(), 'compliance_documents', NEW.id, 'INSERT');
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trigger_audit_compliance_doc"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_matchmaking_after_load_offer"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Invocación asíncrona de la Edge Function mediante pg_net
  -- Nota: Actualizar URL en producción o usar Vault para el dominio base
  PERFORM net.http_post(
    url := 'https://tu-proyecto.supabase.co/functions/v1/matchmaking-engine',
    body := jsonb_build_object('load_offer_id', NEW.id)
  );
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trigger_matchmaking_after_load_offer"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_ocr_auditor"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    payload JSONB;
BEGIN
    payload := jsonb_build_object(
        'type', 'INSERT',
        'table', TG_TABLE_NAME,
        'schema', TG_TABLE_SCHEMA,
        'record', row_to_json(NEW)
    );

    -- Enviar petición asíncrona a la Edge Function
    -- En entorno local, Kong expone las functions en host.docker.internal:54321 o kong:8000
    -- Usaremos la URL pública proporcionada por Supabase local si está disponible
    -- pero para mayor solidez en pg_net usaremos un placeholder reemplazable por variable de entorno 
    -- o directamente la URL local estándar.
    PERFORM net.http_post(
        url := 'http://kong:8000/functions/v1/ocr-auditor',
        body := payload,
        headers := '{"Content-Type": "application/json"}'::jsonb
    );

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trigger_ocr_auditor"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_project_geometry"("p_project_id" "uuid", "p_zone_type" "text", "p_geojson" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'postgis'
    AS $$
DECLARE
  v_geom GEOMETRY;
BEGIN
  -- 1. Convertir el objeto GeoJSON a una Geometría PostGIS pura
  -- ST_GeomFromGeoJSON lee automáticamente el CRS si está presente o asume 4326 si el GeoJSON cumple el estándar
  v_geom := ST_SetSRID(ST_GeomFromGeoJSON(p_geojson::text), 4326);

  -- 2. Inyección dinámica en la columna correspondiente
  IF p_zone_type = 'staging_area' THEN
    UPDATE public.load_offers SET staging_area = v_geom WHERE id = p_project_id;
  ELSIF p_zone_type = 'active_excavation' THEN
    UPDATE public.load_offers SET active_excavation = v_geom WHERE id = p_project_id;
  ELSIF p_zone_type = 'exclusion_zone' THEN
    UPDATE public.load_offers SET exclusion_zone = v_geom WHERE id = p_project_id;
  ELSE
    RAISE EXCEPTION 'Tipo de zona topográfica no reconocida: %', p_zone_type;
  END IF;

  -- Validar si el proyecto existía
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Proyecto UUID % no encontrado en el motor logístico', p_project_id;
  END IF;
END;
$$;


ALTER FUNCTION "public"."update_project_geometry"("p_project_id" "uuid", "p_zone_type" "text", "p_geojson" "jsonb") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."asset_assignments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "driver_id" "uuid" NOT NULL,
    "assigned_by" "uuid" NOT NULL,
    "shift_start" timestamp with time zone DEFAULT "now"() NOT NULL,
    "shift_end" timestamp with time zone,
    "fatigue_override_reason" "text",
    "override_approved_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "status" "public"."assignment_status" DEFAULT 'pending_prestart'::"public"."assignment_status" NOT NULL,
    "prestart_commenced_at" timestamp with time zone,
    CONSTRAINT "chk_shift_dates" CHECK ((("shift_start" < "shift_end") OR ("shift_end" IS NULL)))
);


ALTER TABLE "public"."asset_assignments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."asset_lockouts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "locked_by_operator_uid" "uuid" NOT NULL,
    "prestart_log_id" "uuid",
    "lockout_reason" "text" NOT NULL,
    "status" character varying(20) DEFAULT 'ACTIVE'::character varying,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "released_at" timestamp with time zone,
    "released_by_fitter_uid" "uuid",
    "resolution_notes" "text",
    "project_site_id" "uuid" NOT NULL,
    CONSTRAINT "asset_lockouts_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'RELEASED'::character varying, 'OVERRIDDEN'::character varying])::"text"[])))
);


ALTER TABLE "public"."asset_lockouts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."asset_telemetry_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "recorded_by" "uuid" NOT NULL,
    "event_type" "text" NOT NULL,
    "payload" "jsonb" NOT NULL,
    "client_timestamp" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."asset_telemetry_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."assets" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "internal_code" character varying(100) NOT NULL,
    "category" "public"."asset_category" NOT NULL,
    "status" "public"."asset_status" DEFAULT 'operational'::"public"."asset_status" NOT NULL,
    "current_engine_hours" numeric(10,2),
    "current_odometer" numeric(10,2),
    "required_license_id" "uuid" NOT NULL,
    "last_prestart_at" timestamp with time zone,
    "last_prestart_by_uid" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "hopper_capacity_m3" numeric(5,2) DEFAULT 18.00,
    "baseline_burn_rate_lph" numeric(5,2) DEFAULT 35.00,
    "project_site_id" "uuid" NOT NULL,
    CONSTRAINT "chk_telemetry_match" CHECK (((("category" = 'heavy_machinery'::"public"."asset_category") AND ("current_engine_hours" IS NOT NULL)) OR (("category" = 'light_vehicle'::"public"."asset_category") AND ("current_odometer" IS NOT NULL)) OR ("category" = 'static_plant'::"public"."asset_category")))
);


ALTER TABLE "public"."assets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."assignments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "load_offer_id" "uuid",
    "operator_id" "uuid" NOT NULL,
    "assigned_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."assignments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_contracts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "model" "public"."hire_model_type" NOT NULL,
    "hourly_rate_asset" numeric(10,2) NOT NULL,
    "hourly_rate_operator" numeric(10,2) DEFAULT 0.00,
    "overtime_multiplier" numeric(4,2) DEFAULT 1.50,
    "overtime_threshold_hours" numeric(4,2) DEFAULT 8.00,
    "currency" character varying(3) DEFAULT 'AUD'::character varying,
    "is_active" boolean DEFAULT true,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "erp_contact_id" character varying(255)
);


ALTER TABLE "public"."billing_contracts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_ledger" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "amount_aud" numeric(10,2) NOT NULL,
    "payment_method" character varying(50) DEFAULT 'simulated_card_4242'::character varying,
    "stripe_charge_id" character varying(100) NOT NULL,
    "status" character varying(20) DEFAULT 'succeeded'::character varying,
    "executed_by_uid" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "billing_ledger_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['succeeded'::character varying, 'failed'::character varying, 'refunded'::character varying])::"text"[])))
);


ALTER TABLE "public"."billing_ledger" OWNER TO "postgres";


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


CREATE TABLE IF NOT EXISTS "public"."compliance_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "profile_id" "uuid",
    "doc_type" character varying(50) NOT NULL,
    "file_url" character varying(2048) NOT NULL,
    "expiry_date" "date" NOT NULL,
    "is_verified" boolean DEFAULT false,
    "verified_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."compliance_documents" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cor_incidents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "load_offer_id" "uuid" NOT NULL,
    "operator_id" "uuid" NOT NULL,
    "description" "text" NOT NULL,
    "gps_location" "point" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."cor_incidents" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cor_manifests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "load_offer_id" "uuid",
    "operator_id" "uuid" NOT NULL,
    "action" character varying(50) NOT NULL,
    "loader_signature_hash" character varying(64) NOT NULL,
    "driver_signature_hash" character varying(64) NOT NULL,
    "gps_location" "point" NOT NULL,
    "server_timestamp" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."cor_manifests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dead_letter_queue" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "original_event_id" "uuid" NOT NULL,
    "event_type" "text" NOT NULL,
    "payload" "jsonb" NOT NULL,
    "last_error" "text",
    "failed_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."dead_letter_queue" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."driver_fatigue_evidence" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "load_offer_id" "uuid",
    "operator_id" "uuid" NOT NULL,
    "evidence_url" character varying(2048) NOT NULL,
    "evidence_hash" character varying(64) NOT NULL,
    "upload_timestamp" timestamp with time zone DEFAULT "now"(),
    "gps_location" "point" NOT NULL,
    "status" character varying(20) DEFAULT 'PENDING'::character varying,
    "reviewer_id" "uuid",
    "rejection_reason" "text"
);


ALTER TABLE "public"."driver_fatigue_evidence" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."driver_licenses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "driver_id" "uuid" NOT NULL,
    "license_category_id" "uuid" NOT NULL,
    "issued_date" "date" NOT NULL,
    "expiry_date" "date" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "chk_license_dates" CHECK (("issued_date" < "expiry_date"))
);


ALTER TABLE "public"."driver_licenses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."erp_outbox" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "certificate_id" "uuid",
    "payload" "jsonb" NOT NULL,
    "status" character varying(20) DEFAULT 'pending'::character varying,
    "retry_count" integer DEFAULT 0,
    "next_retry_at" timestamp with time zone DEFAULT "now"(),
    "last_error" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "erp_outbox_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['pending'::character varying, 'processing'::character varying, 'completed'::character varying, 'failed'::character varying, 'dead_letter'::character varying])::"text"[])))
);


ALTER TABLE "public"."erp_outbox" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."excavator_states" (
    "asset_id" "uuid" NOT NULL,
    "operational_status" "public"."excavator_status" DEFAULT 'standby'::"public"."excavator_status" NOT NULL,
    "current_material" "text" DEFAULT 'Unclassified Excavation'::"text" NOT NULL,
    "geological_block" "text",
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE "public"."excavator_states" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."execution_certificates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "assignment_id" "uuid" NOT NULL,
    "contract_id" "uuid" NOT NULL,
    "total_hours" numeric(8,2) NOT NULL,
    "regular_hours" numeric(8,2) NOT NULL,
    "overtime_hours" numeric(8,2) NOT NULL,
    "asset_subtotal" numeric(12,2) NOT NULL,
    "operator_subtotal" numeric(12,2) NOT NULL,
    "total_billable" numeric(12,2) NOT NULL,
    "generated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sync_status" character varying(50) DEFAULT 'pending_erp_export'::character varying,
    "telemetry_source" character varying(50) DEFAULT 'tablet_gps_time'::character varying NOT NULL,
    "telemetry_confidence" numeric(3,2) DEFAULT 0.50 NOT NULL,
    "hardware_engine_hours" numeric(8,2),
    "forensic_pdf_hash" character varying(64),
    "forensic_pdf_url" "text",
    "billed_to_erp_id" character varying(255)
);


ALTER TABLE "public"."execution_certificates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."expense_quarantine" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shift_id" "uuid" NOT NULL,
    "driver_uid" "uuid" NOT NULL,
    "raw_image_url" "text" NOT NULL,
    "ocr_confidence" numeric,
    "extracted_amount" numeric,
    "extracted_vendor" "text",
    "expense_category" character varying(50),
    "status" character varying(20) DEFAULT 'pending_review'::character varying,
    "reviewed_by_uid" "uuid",
    "review_notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "expense_quarantine_expense_category_check" CHECK ((("expense_category")::"text" = ANY ((ARRAY['fuel'::character varying, 'toll'::character varying, 'maintenance_parts'::character varying, 'other'::character varying])::"text"[]))),
    CONSTRAINT "expense_quarantine_ocr_confidence_check" CHECK ((("ocr_confidence" >= (0)::numeric) AND ("ocr_confidence" <= (100)::numeric))),
    CONSTRAINT "expense_quarantine_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['pending_review'::character varying, 'approved'::character varying, 'rejected'::character varying])::"text"[])))
);


ALTER TABLE "public"."expense_quarantine" OWNER TO "postgres";


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


CREATE TABLE IF NOT EXISTS "public"."fleet_billing_ledger" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "project_site_id" "uuid" NOT NULL,
    "billing_date" "date" NOT NULL,
    "active_asset_count" integer DEFAULT 0 NOT NULL,
    "billing_mode" character varying(20) DEFAULT 'SHADOW'::character varying,
    "stripe_reported" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "fleet_billing_ledger_billing_mode_check" CHECK ((("billing_mode")::"text" = ANY ((ARRAY['SHADOW'::character varying, 'LIVE'::character varying, 'DISPUTED'::character varying])::"text"[])))
);


ALTER TABLE "public"."fleet_billing_ledger" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fleet_invites" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "token" character varying(10) NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '24:00:00'::interval) NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "role" character varying(50) DEFAULT 'driver'::character varying,
    "consumed_at" timestamp with time zone,
    "consumed_by_uid" "uuid",
    CONSTRAINT "fleet_invites_role_check" CHECK ((("role")::"text" = ANY ((ARRAY['driver'::character varying, 'fitter'::character varying, 'supervisor'::character varying])::"text"[])))
);


ALTER TABLE "public"."fleet_invites" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fleets" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text",
    "stripe_customer_id" "text",
    "stripe_subscription_id" "text",
    "status" "public"."subscription_status" DEFAULT 'trialing'::"public"."subscription_status" NOT NULL,
    "tier" "public"."subscription_tier" DEFAULT 'tier_1'::"public"."subscription_tier" NOT NULL,
    "trial_start_date" timestamp with time zone DEFAULT "now"(),
    "trial_end_date" timestamp with time zone DEFAULT ("now"() + '30 days'::interval),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "subscription_status" character varying(50) DEFAULT 'ACTIVE'::character varying,
    "grace_period_until" timestamp with time zone
);


ALTER TABLE "public"."fleets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fuel_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "operator_uid" "uuid" NOT NULL,
    "shift_id" "uuid",
    "liters_filled" numeric(6,2) NOT NULL,
    "cost_per_liter" numeric(5,2) DEFAULT 1.85 NOT NULL,
    "total_cost" numeric(8,2) NOT NULL,
    "engine_hours_at_fill" numeric(8,1) NOT NULL,
    "previous_engine_hours" numeric(8,1) NOT NULL,
    "hours_elapsed" numeric(6,1) NOT NULL,
    "burn_rate_lph" numeric(6,2) NOT NULL,
    "haul_cycles_since_last_fill" integer DEFAULT 0 NOT NULL,
    "tonnage_moved_since_last_fill" numeric(8,2) DEFAULT 0.00 NOT NULL,
    "status" character varying(30) NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "fuel_logs_liters_filled_check" CHECK (("liters_filled" > (0)::numeric)),
    CONSTRAINT "fuel_logs_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['VERIFIED'::character varying, 'ANOMALY_HIGH_BURN'::character varying, 'ANOMALY_IDLE_BURN'::character varying, 'THEFT_SUSPECTED'::character varying])::"text"[])))
);


ALTER TABLE "public"."fuel_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."handover_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid",
    "outgoing_user_id" "uuid",
    "incoming_user_id" "uuid",
    "open_incidents_count" integer,
    "signature_timestamp" timestamp with time zone DEFAULT "now"(),
    "signed_by_pin" boolean DEFAULT true
);


ALTER TABLE "public"."handover_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."haul_cycles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "operator_uid" "uuid" NOT NULL,
    "shift_id" "uuid" NOT NULL,
    "route_id" "uuid",
    "material_id" "uuid",
    "state" character varying(20) NOT NULL,
    "tonnage_moved" numeric(8,2) DEFAULT 0.00,
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "loaded_at" timestamp with time zone,
    "dumped_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "cycle_duration_seconds" integer DEFAULT 0,
    "project_site_id" "uuid" NOT NULL,
    CONSTRAINT "haul_cycles_state_check" CHECK ((("state")::"text" = ANY ((ARRAY['LOADING'::character varying, 'HAULING'::character varying, 'DUMPING'::character varying, 'RETURNING'::character varying, 'COMPLETED'::character varying, 'ABORTED'::character varying])::"text"[])))
);


ALTER TABLE "public"."haul_cycles" OWNER TO "postgres";


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


CREATE TABLE IF NOT EXISTS "public"."jit_active_queues" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "joined_queue_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "status" character varying(50) DEFAULT 'waiting'::character varying
);


ALTER TABLE "public"."jit_active_queues" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."license_categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" character varying(50) NOT NULL,
    "description" "text" NOT NULL
);


ALTER TABLE "public"."license_categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."load_cycles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "driver_id" "uuid",
    "weighbridge_operator_id" "uuid",
    "material_type" "text" DEFAULT 'Unclassified Excavation'::"text" NOT NULL,
    "gross_weight" numeric(6,2),
    "tare_weight" numeric(6,2),
    "net_weight" numeric(6,2) GENERATED ALWAYS AS (("gross_weight" - "tare_weight")) STORED,
    "status" "public"."cycle_status" DEFAULT 'loading'::"public"."cycle_status" NOT NULL,
    "loading_started_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "transit_started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "geological_block" "text",
    "reconciled_by" "uuid"
);


ALTER TABLE "public"."load_cycles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."maintenance_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "asset_id" "uuid",
    "issue_description" "text" NOT NULL,
    "locked_by_uid" "uuid",
    "status" character varying(20),
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."maintenance_logs" OWNER TO "postgres";


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


CREATE TABLE IF NOT EXISTS "public"."master_orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "material_type" character varying NOT NULL,
    "target_tonnage" numeric NOT NULL,
    "origin_geofence" "jsonb" NOT NULL,
    "destination_geofence" "jsonb" NOT NULL,
    "requires_4x4_traction" boolean DEFAULT false,
    "max_turn_radius_m" numeric DEFAULT 15.0,
    "status" character varying DEFAULT 'OPEN'::character varying,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid"
);


ALTER TABLE "public"."master_orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."materials" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "name" character varying(50) NOT NULL,
    "density_kg_m3" numeric(6,2) NOT NULL,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."materials" OWNER TO "postgres";


CREATE MATERIALIZED VIEW "public"."mv_ato_fuel_rebate_ledger" AS
 SELECT "f"."fleet_id",
    "f"."asset_id",
    "a"."internal_code" AS "asset_name",
    "a"."category" AS "asset_type",
    "count"("f"."id") AS "total_refuels",
    "sum"("f"."liters_filled") AS "total_liters_injected",
    "sum"("f"."total_cost") AS "total_aud_spent",
    "round"(("sum"("f"."liters_filled") * 0.479), 2) AS "estimated_ato_rebate_aud",
    "round"("avg"("f"."burn_rate_lph"), 2) AS "avg_burn_rate_lph",
    "sum"("f"."tonnage_moved_since_last_fill") AS "total_tonnage_associated",
    "max"("f"."created_at") AS "last_refuel_timestamp"
   FROM ("public"."fuel_logs" "f"
     JOIN "public"."assets" "a" ON (("f"."asset_id" = "a"."id")))
  WHERE (("f"."status")::"text" <> 'THEFT_SUSPECTED'::"text")
  GROUP BY "f"."fleet_id", "f"."asset_id", "a"."internal_code", "a"."category"
  WITH NO DATA;


ALTER MATERIALIZED VIEW "public"."mv_ato_fuel_rebate_ledger" OWNER TO "postgres";


CREATE MATERIALIZED VIEW "public"."mv_daily_cycle_efficiency" AS
 SELECT "project_id",
    "date"("loading_started_at") AS "date",
    "asset_id",
    "count"("id") AS "total_cycles",
    "avg"((EXTRACT(epoch FROM ("transit_started_at" - "loading_started_at")) / 60.0)) AS "avg_loading_minutes"
   FROM "public"."load_cycles"
  WHERE ("transit_started_at" IS NOT NULL)
  GROUP BY "project_id", ("date"("loading_started_at")), "asset_id"
  WITH NO DATA;


ALTER MATERIALIZED VIEW "public"."mv_daily_cycle_efficiency" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."plant_defects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "reported_by" "uuid" NOT NULL,
    "rectified_by" "uuid",
    "defect_description" "text" NOT NULL,
    "status" "public"."defect_status" DEFAULT 'reported'::"public"."defect_status" NOT NULL,
    "reported_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "rectified_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "category" "public"."defect_category",
    "resolution_notes" "text"
);


ALTER TABLE "public"."plant_defects" OWNER TO "postgres";


CREATE MATERIALIZED VIEW "public"."mv_daily_fleet_downtime" AS
 SELECT "project_id",
    "date"("reported_at") AS "date",
    "asset_id",
    "sum"((EXTRACT(epoch FROM (COALESCE("rectified_at", CURRENT_TIMESTAMP) - "reported_at")) / 3600.0)) AS "total_downtime_hours",
    "count"("id") AS "total_defects"
   FROM "public"."plant_defects"
  GROUP BY "project_id", ("date"("reported_at")), "asset_id"
  WITH NO DATA;


ALTER MATERIALIZED VIEW "public"."mv_daily_fleet_downtime" OWNER TO "postgres";


CREATE MATERIALIZED VIEW "public"."mv_daily_production_tonnage" AS
 SELECT "project_id",
    "date"("loading_started_at") AS "date",
    "material_type",
    COALESCE("geological_block", 'UNKNOWN'::"text") AS "geological_block",
    "sum"("net_weight") AS "total_net_weight",
    "count"("id") AS "total_loads"
   FROM "public"."load_cycles"
  WHERE ("net_weight" IS NOT NULL)
  GROUP BY "project_id", ("date"("loading_started_at")), "material_type", COALESCE("geological_block", 'UNKNOWN'::"text")
  WITH NO DATA;


ALTER MATERIALIZED VIEW "public"."mv_daily_production_tonnage" OWNER TO "postgres";


CREATE MATERIALIZED VIEW "public"."mv_predictive_maintenance_roster" AS
 SELECT "a"."id" AS "asset_id",
    "a"."fleet_id",
    "a"."internal_code" AS "asset_name",
    "a"."status" AS "current_whs_status",
    "a"."current_engine_hours",
    (250.0 - "mod"(("a"."current_engine_hours")::numeric, 250.0)) AS "hours_until_next_service",
        CASE
            WHEN ("mod"(("a"."current_engine_hours")::numeric, 250.0) >= 230.0) THEN 'URGENT_SERVICE_DUE'::"text"
            WHEN ("mod"(("a"."current_engine_hours")::numeric, 250.0) >= 200.0) THEN 'SERVICE_WARNING'::"text"
            ELSE 'OPTIMAL_OPERATIONAL'::"text"
        END AS "maintenance_priority",
    "count"("l"."id") AS "active_danger_tags_count"
   FROM ("public"."assets" "a"
     LEFT JOIN "public"."asset_lockouts" "l" ON ((("a"."id" = "l"."asset_id") AND (("l"."status")::"text" = 'ACTIVE'::"text"))))
  GROUP BY "a"."id", "a"."fleet_id", "a"."internal_code", "a"."status", "a"."current_engine_hours"
  WITH NO DATA;


ALTER MATERIALIZED VIEW "public"."mv_predictive_maintenance_roster" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shift_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "operator_uid" "uuid" NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "asset_id" "uuid",
    "status" character varying(30) NOT NULL,
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_state_change_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "accumulated_work_seconds" integer DEFAULT 0 NOT NULL,
    "accumulated_break_seconds" integer DEFAULT 0 NOT NULL,
    "continuous_work_seconds" integer DEFAULT 0 NOT NULL,
    "ended_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "shift_logs_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'ON_BREAK'::character varying, 'COMPLETED'::character varying, 'FATIGUE_LOCKOUT'::character varying])::"text"[])))
);


ALTER TABLE "public"."shift_logs" OWNER TO "postgres";


CREATE MATERIALIZED VIEW "public"."mv_whs_compliance_audit" AS
 SELECT "s"."fleet_id",
    "s"."operator_uid",
    "p"."full_name" AS "operator_name",
    "count"("s"."id") AS "total_shifts_worked",
    "round"((("sum"("s"."accumulated_work_seconds"))::numeric / 3600.0), 2) AS "total_work_hours",
    "round"(("avg"("s"."continuous_work_seconds") / 3600.0), 2) AS "avg_continuous_drive_hours",
    "sum"(
        CASE
            WHEN (("s"."status")::"text" = 'FATIGUE_LOCKOUT'::"text") THEN 1
            ELSE 0
        END) AS "fatigue_lockouts_triggered",
    "max"("s"."started_at") AS "last_shift_start"
   FROM ("public"."shift_logs" "s"
     JOIN "public"."profiles" "p" ON (("s"."operator_uid" = "p"."id")))
  GROUP BY "s"."fleet_id", "s"."operator_uid", "p"."full_name"
  WITH NO DATA;


ALTER MATERIALIZED VIEW "public"."mv_whs_compliance_audit" OWNER TO "postgres";


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


CREATE TABLE IF NOT EXISTS "public"."ocr_audit_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "override_id" "uuid" NOT NULL,
    "vision_model_version" character varying(100) NOT NULL,
    "ocr_confidence_score" numeric,
    "detected_document_type" character varying(100),
    "detected_expiry_date" "date",
    "is_fraud_flagged" boolean DEFAULT false NOT NULL,
    "raw_ocr_dump" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."ocr_audit_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prestart_checks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "assignment_id" "uuid" NOT NULL,
    "operator_id" "uuid" NOT NULL,
    "brakes_checked" boolean DEFAULT false NOT NULL,
    "fluids_checked" boolean DEFAULT false NOT NULL,
    "structural_checked" boolean DEFAULT false NOT NULL,
    "is_safe_to_operate" boolean NOT NULL,
    "defect_notes" "text",
    "inspection_started_at" timestamp with time zone NOT NULL,
    "inspection_completed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "prestart_time_friction" CHECK ((EXTRACT(epoch FROM ("inspection_completed_at" - "inspection_started_at")) >= (60)::numeric))
);


ALTER TABLE "public"."prestart_checks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."project_members" (
    "project_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text"
);


ALTER TABLE "public"."project_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."project_sites" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "name" character varying(255) NOT NULL,
    "status" character varying(50) DEFAULT 'ACTIVE'::character varying,
    "vault_status" character varying(50) DEFAULT 'OPERATIONAL'::character varying,
    "archived_at" timestamp with time zone,
    "purge_scheduled_for" "date",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "project_sites_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'ARCHIVED'::character varying])::"text"[]))),
    CONSTRAINT "project_sites_vault_status_check" CHECK ((("vault_status")::"text" = ANY ((ARRAY['OPERATIONAL'::character varying, 'VAULT_ACTIVE'::character varying, 'VAULT_DELINQUENT'::character varying, 'PURGE_SCHEDULED'::character varying, 'PURGED'::character varying])::"text"[])))
);


ALTER TABLE "public"."project_sites" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."projects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "client_name" "text",
    "project_type" "text",
    "start_date" "date",
    "estimated_end_date" "date",
    "status" "text" DEFAULT 'planning'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "hrcw_polygon" "public"."geometry"(Polygon,4326),
    "loading_pad_geometry" "public"."geometry"(Polygon,4326),
    "loading_pad_buffered" "public"."geometry"(Polygon,4326),
    CONSTRAINT "projects_project_type_check" CHECK (("project_type" = ANY (ARRAY['short_term'::"text", 'long_term'::"text"])))
);


ALTER TABLE "public"."projects" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."role_audit_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "target_user_id" "uuid" NOT NULL,
    "granted_by_user_id" "uuid" NOT NULL,
    "previous_role" "text" NOT NULL,
    "new_role" "text" NOT NULL,
    "action_type" "text",
    "justification" "text" NOT NULL,
    "granted_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "role_audit_logs_action_type_check" CHECK (("action_type" = ANY (ARRAY['ELEVATION'::"text", 'REVOCATION'::"text"])))
);


ALTER TABLE "public"."role_audit_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."routes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "name" character varying(100) NOT NULL,
    "origin_zone" character varying(50) NOT NULL,
    "destination_zone" character varying(50) NOT NULL,
    "est_duration_minutes" integer DEFAULT 15,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."routes" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."secure_daily_cycle_efficiency" AS
 SELECT "project_id",
    "date",
    "asset_id",
    "total_cycles",
    "avg_loading_minutes"
   FROM "public"."mv_daily_cycle_efficiency"
  WHERE ("project_id" IN ( SELECT "project_members"."project_id"
           FROM "public"."project_members"
          WHERE ("project_members"."user_id" = "auth"."uid"())));


ALTER VIEW "public"."secure_daily_cycle_efficiency" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."secure_daily_fleet_downtime" AS
 SELECT "project_id",
    "date",
    "asset_id",
    "total_downtime_hours",
    "total_defects"
   FROM "public"."mv_daily_fleet_downtime"
  WHERE ("project_id" IN ( SELECT "project_members"."project_id"
           FROM "public"."project_members"
          WHERE ("project_members"."user_id" = "auth"."uid"())));


ALTER VIEW "public"."secure_daily_fleet_downtime" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."secure_daily_production_tonnage" AS
 SELECT "project_id",
    "date",
    "material_type",
    "geological_block",
    "total_net_weight",
    "total_loads"
   FROM "public"."mv_daily_production_tonnage"
  WHERE ("project_id" IN ( SELECT "project_members"."project_id"
           FROM "public"."project_members"
          WHERE ("project_members"."user_id" = "auth"."uid"())));


ALTER VIEW "public"."secure_daily_production_tonnage" OWNER TO "postgres";


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


CREATE TABLE IF NOT EXISTS "public"."shift_assignments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "master_order_id" "uuid",
    "driver_id" "uuid",
    "vehicle_id" "uuid",
    "status" character varying DEFAULT 'ACTIVE'::character varying,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "assigned_by" "uuid",
    "intent_to_detach" boolean DEFAULT false,
    "detach_reason" character varying
);


ALTER TABLE "public"."shift_assignments" OWNER TO "postgres";


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


CREATE TABLE IF NOT EXISTS "public"."structural_elements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "load_offer_id" "uuid",
    "bim_guid" character varying(255) NOT NULL,
    "element_type" character varying(100) NOT NULL,
    "length_mm" integer NOT NULL,
    "width_mm" integer NOT NULL,
    "weight_kg" numeric(8,2) NOT NULL
);


ALTER TABLE "public"."structural_elements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."system_audit_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "actor_uid" "uuid",
    "actor_role" "text",
    "action_type" character varying(50) NOT NULL,
    "target_table" character varying(100) NOT NULL,
    "target_record_id" "uuid",
    "payload_before" "jsonb",
    "payload_after" "jsonb",
    "client_ip" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."system_audit_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."system_config" (
    "key" "text" NOT NULL,
    "value" "jsonb" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."system_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."telemetry_dead_letter_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "asset_id" "uuid",
    "recorded_by" "uuid",
    "event_type" "text",
    "payload" "jsonb",
    "client_timestamp" timestamp with time zone,
    "error_code" "text",
    "error_message" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."telemetry_dead_letter_logs" OWNER TO "postgres";


CREATE UNLOGGED TABLE "public"."telemetry_inbox" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "recorded_by" "uuid" NOT NULL,
    "payload" "jsonb" NOT NULL,
    "client_timestamp" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."telemetry_inbox" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."telemetry_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "engine_hours" numeric(10,2) NOT NULL,
    "fuel_level_percent" numeric(5,2),
    "coolant_temp_celsius" numeric(5,2),
    "is_engine_running" boolean DEFAULT false NOT NULL,
    "recorded_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."telemetry_logs" OWNER TO "postgres";


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


CREATE TABLE IF NOT EXISTS "public"."vehicles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "profile_id" "uuid" NOT NULL,
    "registration_plate" character varying(20) NOT NULL,
    "tare_weight" numeric NOT NULL,
    "gvm_limit" numeric NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."vehicles" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."view_cor_audit_timeline" AS
 SELECT "lo"."id" AS "load_id",
    "lo"."status",
    "lo"."anomaly_flag",
    "lo"."anomaly_resolution_reason",
    "lo"."anomaly_resolution_tags",
    "lo"."anomaly_resolved_at" AS "resolved_at",
    "lo"."created_at",
    "lo"."completed_at_local",
    "lo"."digital_bypass",
    "lo"."paper_docket_ref",
    "lo"."docket_image_path",
    "p1"."full_name" AS "operator_id",
    "p2"."full_name" AS "bypassed_by_name"
   FROM (("public"."load_offers" "lo"
     LEFT JOIN "public"."profiles" "p1" ON (("lo"."driver_id" = "p1"."id")))
     LEFT JOIN "public"."profiles" "p2" ON (("lo"."bypassed_by" = "p2"."id")))
  ORDER BY "lo"."created_at" DESC;


ALTER VIEW "public"."view_cor_audit_timeline" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."view_driver_fatigue" AS
 SELECT "a"."operator_id" AS "driver_id",
    "min"("lo"."created_at") AS "shift_start",
    (EXTRACT(epoch FROM ("now"() - "min"("lo"."created_at"))) / (3600)::numeric) AS "hours_active",
    "count"("lo"."id") AS "trips_today"
   FROM ("public"."assignments" "a"
     JOIN "public"."load_offers" "lo" ON (("a"."load_offer_id" = "lo"."id")))
  WHERE ("lo"."created_at" > CURRENT_DATE)
  GROUP BY "a"."operator_id";


ALTER VIEW "public"."view_driver_fatigue" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."view_fleet_matrix" AS
 SELECT "a"."id" AS "asset_id",
    "a"."fleet_id",
    "a"."project_site_id",
    "a"."internal_code",
    "a"."category",
    "a"."status" AS "asset_status",
    "p"."name" AS "project_name"
   FROM ("public"."assets" "a"
     JOIN "public"."project_sites" "p" ON (("p"."id" = "a"."project_site_id")))
  WHERE (("a"."status" = 'operational'::"public"."asset_status") AND (NOT (EXISTS ( SELECT 1
           FROM "public"."asset_lockouts" "l"
          WHERE (("l"."asset_id" = "a"."id") AND (("l"."status")::"text" = 'ACTIVE'::"text"))))));


ALTER VIEW "public"."view_fleet_matrix" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."view_project_progress" AS
 SELECT "material_type",
    "count"("id") AS "total_trips",
    "sum"(COALESCE("ocr_mass_extracted", "loaded_gross_mass")) AS "total_mass_delivered_kg"
   FROM "public"."load_offers"
  WHERE (("status")::"text" = 'COMPLETED'::"text")
  GROUP BY "material_type";


ALTER VIEW "public"."view_project_progress" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."view_site_bottlenecks" AS
 SELECT "staging_area" AS "geofence_zone",
    "count"("id") AS "active_trucks",
    "avg"((EXTRACT(epoch FROM ("completed_at_local" - "created_at")) / (60)::numeric)) AS "avg_cycle_time_mins"
   FROM "public"."load_offers"
  WHERE (("status")::"text" = ANY ((ARRAY['LOADING'::character varying, 'IN_TRANSIT'::character varying])::"text"[]))
  GROUP BY "staging_area";


ALTER VIEW "public"."view_site_bottlenecks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."whs_prestart_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "operator_uid" "uuid" NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "checklist_data" "jsonb" NOT NULL,
    "defect_notes" "jsonb" DEFAULT '{}'::"jsonb",
    "passed" boolean NOT NULL,
    "client_timestamp" timestamp with time zone NOT NULL,
    "server_timestamp" timestamp with time zone DEFAULT "now"(),
    "project_site_id" "uuid" NOT NULL
);


ALTER TABLE "public"."whs_prestart_logs" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."vw_daily_billable_assets" AS
 SELECT DISTINCT "whs_prestart_logs"."fleet_id",
    "whs_prestart_logs"."project_site_id",
    "whs_prestart_logs"."asset_id",
    "date"(("whs_prestart_logs"."server_timestamp" AT TIME ZONE 'Australia/Hobart'::"text")) AS "operational_date"
   FROM "public"."whs_prestart_logs"
UNION
 SELECT DISTINCT "haul_cycles"."fleet_id",
    "haul_cycles"."project_site_id",
    "haul_cycles"."asset_id",
    "date"(("haul_cycles"."started_at" AT TIME ZONE 'Australia/Hobart'::"text")) AS "operational_date"
   FROM "public"."haul_cycles"
UNION
 SELECT DISTINCT "asset_lockouts"."fleet_id",
    "asset_lockouts"."project_site_id",
    "asset_lockouts"."asset_id",
    "date"(("asset_lockouts"."created_at" AT TIME ZONE 'Australia/Hobart'::"text")) AS "operational_date"
   FROM "public"."asset_lockouts";


ALTER VIEW "public"."vw_daily_billable_assets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."webhook_endpoints" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fleet_id" "uuid" NOT NULL,
    "event_type" character varying(100) NOT NULL,
    "target_url" "text" NOT NULL,
    "auth_secret" "text",
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."webhook_endpoints" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."webhook_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "event_type" character varying(255) NOT NULL,
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "status" character varying(50) DEFAULT 'pending'::character varying,
    "request_id" bigint,
    "retry_count" integer DEFAULT 0,
    "next_retry_at" timestamp with time zone DEFAULT "now"(),
    "error_message" "text"
);


ALTER TABLE "public"."webhook_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."whs_overrides" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "supervisor_id" "uuid" NOT NULL,
    "driver_id" "uuid" NOT NULL,
    "document_path" "text" NOT NULL,
    "new_expiry_date" "date" NOT NULL,
    "override_timestamp" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."whs_overrides" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."whs_prestarts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "operator_id" "uuid" NOT NULL,
    "checklist_data" "jsonb" NOT NULL,
    "defect_notes" "jsonb",
    "passed" boolean NOT NULL,
    "client_timestamp" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."whs_prestarts" OWNER TO "postgres";


ALTER TABLE ONLY "public"."access_logs"
    ADD CONSTRAINT "access_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."asset_assignments"
    ADD CONSTRAINT "asset_assignments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."asset_lockouts"
    ADD CONSTRAINT "asset_lockouts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."asset_telemetry_logs"
    ADD CONSTRAINT "asset_telemetry_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."assignments"
    ADD CONSTRAINT "assignments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_contracts"
    ADD CONSTRAINT "billing_contracts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_ledger"
    ADD CONSTRAINT "billing_ledger_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_ledger"
    ADD CONSTRAINT "billing_ledger_stripe_charge_id_key" UNIQUE ("stripe_charge_id");



ALTER TABLE ONLY "public"."clients"
    ADD CONSTRAINT "clients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."compliance_documents"
    ADD CONSTRAINT "compliance_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cor_incidents"
    ADD CONSTRAINT "cor_incidents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cor_manifests"
    ADD CONSTRAINT "cor_manifests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dead_letter_queue"
    ADD CONSTRAINT "dead_letter_queue_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."driver_fatigue_evidence"
    ADD CONSTRAINT "driver_fatigue_evidence_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."driver_licenses"
    ADD CONSTRAINT "driver_licenses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."erp_outbox"
    ADD CONSTRAINT "erp_outbox_certificate_id_key" UNIQUE ("certificate_id");



ALTER TABLE ONLY "public"."erp_outbox"
    ADD CONSTRAINT "erp_outbox_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."excavator_states"
    ADD CONSTRAINT "excavator_states_pkey" PRIMARY KEY ("asset_id");



ALTER TABLE ONLY "public"."asset_assignments"
    ADD CONSTRAINT "exclude_overlapping_asset_shifts" EXCLUDE USING "gist" ("asset_id" WITH =, "tstzrange"("shift_start", COALESCE("shift_end", 'infinity'::timestamp with time zone)) WITH &&);



ALTER TABLE ONLY "public"."asset_assignments"
    ADD CONSTRAINT "exclude_overlapping_driver_shifts" EXCLUDE USING "gist" ("driver_id" WITH =, "tstzrange"("shift_start", COALESCE("shift_end", 'infinity'::timestamp with time zone)) WITH &&);



ALTER TABLE ONLY "public"."execution_certificates"
    ADD CONSTRAINT "execution_certificates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."expense_quarantine"
    ADD CONSTRAINT "expense_quarantine_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fatigue_logs"
    ADD CONSTRAINT "fatigue_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fleet_billing_ledger"
    ADD CONSTRAINT "fleet_billing_ledger_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fleet_invites"
    ADD CONSTRAINT "fleet_invites_invite_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."fleet_invites"
    ADD CONSTRAINT "fleet_invites_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fleets"
    ADD CONSTRAINT "fleets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fleets"
    ADD CONSTRAINT "fleets_stripe_customer_id_key" UNIQUE ("stripe_customer_id");



ALTER TABLE ONLY "public"."fleets"
    ADD CONSTRAINT "fleets_stripe_subscription_id_key" UNIQUE ("stripe_subscription_id");



ALTER TABLE ONLY "public"."fuel_logs"
    ADD CONSTRAINT "fuel_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."handover_logs"
    ADD CONSTRAINT "handover_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."haul_cycles"
    ADD CONSTRAINT "haul_cycles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_invoice_number_key" UNIQUE ("invoice_number");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."jit_active_queues"
    ADD CONSTRAINT "jit_active_queues_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."jit_active_queues"
    ADD CONSTRAINT "jit_active_queues_project_id_asset_id_status_key" UNIQUE ("project_id", "asset_id", "status");



ALTER TABLE ONLY "public"."license_categories"
    ADD CONSTRAINT "license_categories_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."license_categories"
    ADD CONSTRAINT "license_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."load_cycles"
    ADD CONSTRAINT "load_cycles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."load_offers"
    ADD CONSTRAINT "load_offers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."maintenance_logs"
    ADD CONSTRAINT "maintenance_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."maintenance_schedules"
    ADD CONSTRAINT "maintenance_schedules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."master_orders"
    ADD CONSTRAINT "master_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."materials"
    ADD CONSTRAINT "materials_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nhvr_compliance_logs"
    ADD CONSTRAINT "nhvr_compliance_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nodes"
    ADD CONSTRAINT "nodes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ocr_audit_logs"
    ADD CONSTRAINT "ocr_audit_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."plant_defects"
    ADD CONSTRAINT "plant_defects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prestart_checks"
    ADD CONSTRAINT "prestart_checks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_pkey" PRIMARY KEY ("project_id", "user_id");



ALTER TABLE ONLY "public"."project_sites"
    ADD CONSTRAINT "project_sites_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."role_audit_logs"
    ADD CONSTRAINT "role_audit_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."routes"
    ADD CONSTRAINT "routes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."service_logs"
    ADD CONSTRAINT "service_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shift_assignments"
    ADD CONSTRAINT "shift_assignments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shift_logs"
    ADD CONSTRAINT "shift_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sos_alerts"
    ADD CONSTRAINT "sos_alerts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."structural_elements"
    ADD CONSTRAINT "structural_elements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."system_audit_logs"
    ADD CONSTRAINT "system_audit_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."system_config"
    ADD CONSTRAINT "system_config_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."telemetry_dead_letter_logs"
    ADD CONSTRAINT "telemetry_dead_letter_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."telemetry_inbox"
    ADD CONSTRAINT "telemetry_inbox_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."telemetry_logs"
    ADD CONSTRAINT "telemetry_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."trip_waypoints"
    ADD CONSTRAINT "trip_waypoints_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."trips"
    ADD CONSTRAINT "trips_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."assignments"
    ADD CONSTRAINT "unique_assignment" UNIQUE ("load_offer_id");



ALTER TABLE ONLY "public"."billing_contracts"
    ADD CONSTRAINT "uq_active_contract" UNIQUE ("asset_id");



ALTER TABLE ONLY "public"."execution_certificates"
    ADD CONSTRAINT "uq_assignment_certificate" UNIQUE ("assignment_id");



ALTER TABLE ONLY "public"."webhook_endpoints"
    ADD CONSTRAINT "uq_fleet_event_url" UNIQUE ("fleet_id", "event_type", "target_url");



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "uq_fleet_internal_code" UNIQUE ("fleet_id", "internal_code");



ALTER TABLE ONLY "public"."fleet_billing_ledger"
    ADD CONSTRAINT "uq_project_daily_billing" UNIQUE ("project_site_id", "billing_date");



ALTER TABLE ONLY "public"."vehicles"
    ADD CONSTRAINT "vehicles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."webhook_endpoints"
    ADD CONSTRAINT "webhook_endpoints_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."webhook_events"
    ADD CONSTRAINT "webhook_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."whs_overrides"
    ADD CONSTRAINT "whs_overrides_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."whs_prestart_logs"
    ADD CONSTRAINT "whs_prestart_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."whs_prestarts"
    ADD CONSTRAINT "whs_prestarts_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_access_logs_timestamp" ON "public"."access_logs" USING "btree" ("timestamp" DESC);



CREATE UNIQUE INDEX "idx_active_asset_haul_cycle" ON "public"."haul_cycles" USING "btree" ("asset_id") WHERE (("state")::"text" <> ALL ((ARRAY['COMPLETED'::character varying, 'ABORTED'::character varying])::"text"[]));



CREATE INDEX "idx_active_lockouts" ON "public"."asset_lockouts" USING "btree" ("asset_id") WHERE (("status")::"text" = 'ACTIVE'::"text");



CREATE UNIQUE INDEX "idx_active_operator_shift" ON "public"."shift_logs" USING "btree" ("operator_uid") WHERE (("status")::"text" = ANY ((ARRAY['ACTIVE'::character varying, 'ON_BREAK'::character varying, 'FATIGUE_LOCKOUT'::character varying])::"text"[]));



CREATE INDEX "idx_billing_contracts_erp_contact" ON "public"."billing_contracts" USING "btree" ("erp_contact_id");



CREATE INDEX "idx_fleet_invites_token" ON "public"."fleet_invites" USING "btree" ("token") WHERE ("consumed_at" IS NULL);



CREATE INDEX "idx_load_offers_location" ON "public"."load_offers" USING "gist" ("public"."ll_to_earth"(("destination_lat")::double precision, ("destination_lng")::double precision));



CREATE UNIQUE INDEX "idx_mv_ato_fuel_asset" ON "public"."mv_ato_fuel_rebate_ledger" USING "btree" ("asset_id");



CREATE UNIQUE INDEX "idx_mv_daily_cycle_efficiency" ON "public"."mv_daily_cycle_efficiency" USING "btree" ("project_id", "date", "asset_id");



CREATE UNIQUE INDEX "idx_mv_daily_fleet_downtime" ON "public"."mv_daily_fleet_downtime" USING "btree" ("project_id", "date", "asset_id");



CREATE UNIQUE INDEX "idx_mv_daily_production_tonnage" ON "public"."mv_daily_production_tonnage" USING "btree" ("project_id", "date", "material_type", "geological_block");



CREATE UNIQUE INDEX "idx_mv_maint_asset" ON "public"."mv_predictive_maintenance_roster" USING "btree" ("asset_id");



CREATE UNIQUE INDEX "idx_mv_whs_operator" ON "public"."mv_whs_compliance_audit" USING "btree" ("operator_uid");



CREATE INDEX "idx_projects_hrcw_polygon" ON "public"."projects" USING "gist" ("hrcw_polygon");



CREATE INDEX "idx_projects_loading_pad_buffered" ON "public"."projects" USING "gist" ("loading_pad_buffered");



CREATE INDEX "idx_projects_loading_pad_geometry" ON "public"."projects" USING "gist" ("loading_pad_geometry");



CREATE INDEX "idx_structural_elements_guid" ON "public"."structural_elements" USING "btree" ("bim_guid");



CREATE INDEX "idx_telemetry_asset_time" ON "public"."telemetry_logs" USING "btree" ("asset_id", "recorded_at" DESC);



CREATE OR REPLACE TRIGGER "audit_cor_manifests" AFTER INSERT OR DELETE OR UPDATE ON "public"."cor_manifests" FOR EACH ROW EXECUTE FUNCTION "public"."audit_log_changes"();



CREATE OR REPLACE TRIGGER "audit_load_offers" AFTER INSERT OR DELETE OR UPDATE ON "public"."load_offers" FOR EACH ROW EXECUTE FUNCTION "public"."audit_log_changes"();



CREATE OR REPLACE TRIGGER "on_cor_incident_audit" AFTER INSERT OR DELETE OR UPDATE ON "public"."cor_incidents" FOR EACH ROW EXECUTE FUNCTION "public"."audit_log_changes"();



CREATE OR REPLACE TRIGGER "tr_default_project_site_assets" BEFORE INSERT ON "public"."assets" FOR EACH ROW EXECUTE FUNCTION "public"."fn_default_project_site"();



CREATE OR REPLACE TRIGGER "tr_default_project_site_haul" BEFORE INSERT ON "public"."haul_cycles" FOR EACH ROW EXECUTE FUNCTION "public"."fn_default_project_site"();



CREATE OR REPLACE TRIGGER "tr_default_project_site_lockouts" BEFORE INSERT ON "public"."asset_lockouts" FOR EACH ROW EXECUTE FUNCTION "public"."fn_default_project_site"();



CREATE OR REPLACE TRIGGER "tr_default_project_site_prestart" BEFORE INSERT ON "public"."whs_prestart_logs" FOR EACH ROW EXECUTE FUNCTION "public"."fn_default_project_site"();



CREATE OR REPLACE TRIGGER "tr_enforce_validity_haul" BEFORE INSERT ON "public"."haul_cycles" FOR EACH ROW EXECUTE FUNCTION "public"."fn_enforce_operator_validity"();



CREATE OR REPLACE TRIGGER "tr_enforce_validity_lockouts" BEFORE INSERT ON "public"."asset_lockouts" FOR EACH ROW EXECUTE FUNCTION "public"."fn_enforce_operator_validity"();



CREATE OR REPLACE TRIGGER "tr_enforce_validity_prestart" BEFORE INSERT ON "public"."whs_prestart_logs" FOR EACH ROW EXECUTE FUNCTION "public"."fn_enforce_operator_validity"();



CREATE OR REPLACE TRIGGER "tr_guard_asset_site_transfer" BEFORE UPDATE OF "project_site_id" ON "public"."assets" FOR EACH ROW EXECUTE FUNCTION "public"."fn_guard_asset_site_transfer"();



CREATE OR REPLACE TRIGGER "tr_solvency_guard_haul" BEFORE INSERT OR UPDATE ON "public"."haul_cycles" FOR EACH ROW EXECUTE FUNCTION "public"."fn_enforce_solvency_lockdown"();



CREATE OR REPLACE TRIGGER "tr_solvency_guard_lockouts" BEFORE INSERT OR UPDATE ON "public"."asset_lockouts" FOR EACH ROW EXECUTE FUNCTION "public"."fn_enforce_solvency_lockdown"();



CREATE OR REPLACE TRIGGER "tr_solvency_guard_prestart" BEFORE INSERT OR UPDATE ON "public"."whs_prestart_logs" FOR EACH ROW EXECUTE FUNCTION "public"."fn_enforce_solvency_lockdown"();



CREATE OR REPLACE TRIGGER "trg_after_compliance_doc_upload" AFTER INSERT ON "public"."compliance_documents" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_audit_compliance_doc"();



CREATE OR REPLACE TRIGGER "trg_after_load_offer_insert" AFTER INSERT ON "public"."load_offers" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_matchmaking_after_load_offer"();



CREATE OR REPLACE TRIGGER "trg_audit_billing_contracts" AFTER INSERT OR DELETE OR UPDATE ON "public"."billing_contracts" FOR EACH ROW EXECUTE FUNCTION "public"."log_infrastructure_mutation"();



CREATE OR REPLACE TRIGGER "trg_autoloop_on_complete" AFTER INSERT OR UPDATE ON "public"."load_offers" FOR EACH ROW EXECUTE FUNCTION "public"."fn_trigger_autoloop"();



CREATE OR REPLACE TRIGGER "trg_before_dispatch" BEFORE INSERT OR UPDATE ON "public"."asset_assignments" FOR EACH ROW EXECUTE FUNCTION "public"."trg_validate_dispatch"();



CREATE OR REPLACE TRIGGER "trg_certificate_webhook" AFTER INSERT ON "public"."execution_certificates" FOR EACH ROW EXECUTE FUNCTION "public"."notify_edge_function_on_certificate"();



CREATE OR REPLACE TRIGGER "trg_check_active_defects_shift" BEFORE INSERT ON "public"."shift_assignments" FOR EACH ROW EXECUTE FUNCTION "public"."check_active_defects_before_shift"();



CREATE OR REPLACE TRIGGER "trg_close_shift_billing" AFTER UPDATE OF "status" ON "public"."asset_assignments" FOR EACH ROW EXECUTE FUNCTION "public"."generate_execution_certificate"();



CREATE OR REPLACE TRIGGER "trg_critical_audit_webhook" AFTER INSERT ON "public"."system_audit_logs" FOR EACH ROW EXECUTE FUNCTION "public"."notify_edge_function_on_critical_audit"();



CREATE OR REPLACE TRIGGER "trg_enforce_whs_lockout" BEFORE UPDATE ON "public"."assets" FOR EACH ROW EXECUTE FUNCTION "public"."fn_enforce_whs_lockout"();



CREATE OR REPLACE TRIGGER "trg_enqueue_outbox" AFTER UPDATE OF "forensic_pdf_hash" ON "public"."execution_certificates" FOR EACH ROW WHEN ((("old"."forensic_pdf_hash" IS NULL) AND ("new"."forensic_pdf_hash" IS NOT NULL))) EXECUTE FUNCTION "public"."queue_erp_outbox"();



CREATE OR REPLACE TRIGGER "trg_guard_profile_privileges" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."fn_guard_profile_privileges"();



CREATE OR REPLACE TRIGGER "trg_intercept_handover" BEFORE INSERT ON "public"."asset_telemetry_logs" FOR EACH ROW EXECUTE FUNCTION "public"."process_handover_signature"();



CREATE OR REPLACE TRIGGER "trg_iot_safety_check" AFTER INSERT ON "public"."telemetry_logs" FOR EACH ROW EXECUTE FUNCTION "public"."process_telemetry_safety_override"();



CREATE OR REPLACE TRIGGER "trg_maintenance_lock_webhook" AFTER INSERT ON "public"."asset_lockouts" FOR EACH ROW EXECUTE FUNCTION "public"."notify_edge_function_on_lock"();



CREATE OR REPLACE TRIGGER "trg_matchmaker_on_excavator_ready" AFTER UPDATE ON "public"."excavator_states" FOR EACH ROW EXECUTE FUNCTION "public"."matchmaker_dispatch_on_excavator_ready"();



CREATE OR REPLACE TRIGGER "trg_project_asset_telemetry" AFTER INSERT ON "public"."asset_telemetry_logs" FOR EACH ROW EXECUTE FUNCTION "public"."project_asset_telemetry_state"();



CREATE OR REPLACE TRIGGER "trg_protect_pdf_hash" BEFORE UPDATE ON "public"."execution_certificates" FOR EACH ROW EXECUTE FUNCTION "public"."protect_forensic_hash"();



CREATE OR REPLACE TRIGGER "trg_push_to_n8n_webhook" BEFORE INSERT ON "public"."webhook_events" FOR EACH ROW EXECUTE FUNCTION "public"."push_to_n8n_webhook"();



CREATE OR REPLACE TRIGGER "trg_sync_asset_status_on_defect" AFTER INSERT OR UPDATE OF "status" ON "public"."plant_defects" FOR EACH ROW EXECUTE FUNCTION "public"."sync_asset_status_on_defect"();



CREATE OR REPLACE TRIGGER "trigger_block_uninsured_contractor" BEFORE INSERT ON "public"."load_offers" FOR EACH ROW EXECUTE FUNCTION "public"."check_insurance_compliance"();



CREATE OR REPLACE TRIGGER "trigger_buffer_loading_pad" BEFORE INSERT OR UPDATE OF "loading_pad_geometry" ON "public"."projects" FOR EACH ROW EXECUTE FUNCTION "public"."calculate_buffered_loading_pad"();



CREATE OR REPLACE TRIGGER "trigger_lock_structural_elements" BEFORE DELETE OR UPDATE ON "public"."structural_elements" FOR EACH ROW EXECUTE FUNCTION "public"."protect_contract_lifecycle"();



CREATE OR REPLACE TRIGGER "trigger_simulate_docket_ocr" BEFORE UPDATE ON "public"."load_offers" FOR EACH ROW EXECUTE FUNCTION "public"."simulate_docket_ocr"();



CREATE OR REPLACE TRIGGER "webhook_trigger_ocr_auditor" AFTER INSERT ON "public"."whs_overrides" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_ocr_auditor"();



ALTER TABLE ONLY "public"."access_logs"
    ADD CONSTRAINT "access_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."asset_assignments"
    ADD CONSTRAINT "asset_assignments_asset_id_fkey" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."asset_assignments"
    ADD CONSTRAINT "asset_assignments_assigned_by_fkey" FOREIGN KEY ("assigned_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."asset_assignments"
    ADD CONSTRAINT "asset_assignments_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."asset_assignments"
    ADD CONSTRAINT "asset_assignments_fleet_id_fkey" FOREIGN KEY ("fleet_id") REFERENCES "public"."fleets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."asset_assignments"
    ADD CONSTRAINT "asset_assignments_override_approved_by_fkey" FOREIGN KEY ("override_approved_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."asset_lockouts"
    ADD CONSTRAINT "asset_lockouts_locked_by_operator_uid_fkey" FOREIGN KEY ("locked_by_operator_uid") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."asset_lockouts"
    ADD CONSTRAINT "asset_lockouts_prestart_log_id_fkey" FOREIGN KEY ("prestart_log_id") REFERENCES "public"."whs_prestart_logs"("id");



ALTER TABLE ONLY "public"."asset_lockouts"
    ADD CONSTRAINT "asset_lockouts_project_site_id_fkey" FOREIGN KEY ("project_site_id") REFERENCES "public"."project_sites"("id");



ALTER TABLE ONLY "public"."asset_telemetry_logs"
    ADD CONSTRAINT "asset_telemetry_logs_recorded_by_fkey" FOREIGN KEY ("recorded_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_fleet_id_fkey" FOREIGN KEY ("fleet_id") REFERENCES "public"."fleets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_project_site_id_fkey" FOREIGN KEY ("project_site_id") REFERENCES "public"."project_sites"("id");



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_required_license_id_fkey" FOREIGN KEY ("required_license_id") REFERENCES "public"."license_categories"("id");



ALTER TABLE ONLY "public"."assignments"
    ADD CONSTRAINT "assignments_load_offer_id_fkey" FOREIGN KEY ("load_offer_id") REFERENCES "public"."load_offers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_contracts"
    ADD CONSTRAINT "billing_contracts_asset_id_fkey" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_ledger"
    ADD CONSTRAINT "billing_ledger_executed_by_uid_fkey" FOREIGN KEY ("executed_by_uid") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."billing_ledger"
    ADD CONSTRAINT "billing_ledger_fleet_id_fkey" FOREIGN KEY ("fleet_id") REFERENCES "public"."fleets"("id");



ALTER TABLE ONLY "public"."compliance_documents"
    ADD CONSTRAINT "compliance_documents_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cor_incidents"
    ADD CONSTRAINT "cor_incidents_load_offer_id_fkey" FOREIGN KEY ("load_offer_id") REFERENCES "public"."load_offers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cor_incidents"
    ADD CONSTRAINT "cor_incidents_operator_id_fkey" FOREIGN KEY ("operator_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."cor_manifests"
    ADD CONSTRAINT "cor_manifests_load_offer_id_fkey" FOREIGN KEY ("load_offer_id") REFERENCES "public"."load_offers"("id");



ALTER TABLE ONLY "public"."driver_fatigue_evidence"
    ADD CONSTRAINT "driver_fatigue_evidence_load_offer_id_fkey" FOREIGN KEY ("load_offer_id") REFERENCES "public"."load_offers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."driver_licenses"
    ADD CONSTRAINT "driver_licenses_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."driver_licenses"
    ADD CONSTRAINT "driver_licenses_license_category_id_fkey" FOREIGN KEY ("license_category_id") REFERENCES "public"."license_categories"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."erp_outbox"
    ADD CONSTRAINT "erp_outbox_certificate_id_fkey" FOREIGN KEY ("certificate_id") REFERENCES "public"."execution_certificates"("id");



ALTER TABLE ONLY "public"."execution_certificates"
    ADD CONSTRAINT "execution_certificates_assignment_id_fkey" FOREIGN KEY ("assignment_id") REFERENCES "public"."asset_assignments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."execution_certificates"
    ADD CONSTRAINT "execution_certificates_contract_id_fkey" FOREIGN KEY ("contract_id") REFERENCES "public"."billing_contracts"("id");



ALTER TABLE ONLY "public"."expense_quarantine"
    ADD CONSTRAINT "expense_quarantine_driver_uid_fkey" FOREIGN KEY ("driver_uid") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."expense_quarantine"
    ADD CONSTRAINT "expense_quarantine_reviewed_by_uid_fkey" FOREIGN KEY ("reviewed_by_uid") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."expense_quarantine"
    ADD CONSTRAINT "expense_quarantine_shift_id_fkey" FOREIGN KEY ("shift_id") REFERENCES "public"."asset_assignments"("id");



ALTER TABLE ONLY "public"."asset_lockouts"
    ADD CONSTRAINT "fk_asset_lockouts_asset_id" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "fk_client" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."trips"
    ADD CONSTRAINT "fk_driver" FOREIGN KEY ("driver_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."service_logs"
    ADD CONSTRAINT "fk_mechanic_node" FOREIGN KEY ("mechanic_node_id") REFERENCES "public"."nodes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."trip_waypoints"
    ADD CONSTRAINT "fk_node" FOREIGN KEY ("node_id") REFERENCES "public"."nodes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "fk_profiles_fleet_id" FOREIGN KEY ("fleet_id") REFERENCES "public"."fleets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "fk_trip" FOREIGN KEY ("trip_id") REFERENCES "public"."trips"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."trip_waypoints"
    ADD CONSTRAINT "fk_trip" FOREIGN KEY ("trip_id") REFERENCES "public"."trips"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sos_alerts"
    ADD CONSTRAINT "fk_trip" FOREIGN KEY ("trip_id") REFERENCES "public"."trips"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fleet_billing_ledger"
    ADD CONSTRAINT "fleet_billing_ledger_fleet_id_fkey" FOREIGN KEY ("fleet_id") REFERENCES "public"."fleets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fleet_billing_ledger"
    ADD CONSTRAINT "fleet_billing_ledger_project_site_id_fkey" FOREIGN KEY ("project_site_id") REFERENCES "public"."project_sites"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fleet_invites"
    ADD CONSTRAINT "fleet_invites_consumed_by_uid_fkey" FOREIGN KEY ("consumed_by_uid") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."fleet_invites"
    ADD CONSTRAINT "fleet_invites_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."fleet_invites"
    ADD CONSTRAINT "fleet_invites_fleet_id_fkey" FOREIGN KEY ("fleet_id") REFERENCES "public"."fleets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."fuel_logs"
    ADD CONSTRAINT "fuel_logs_asset_id_fkey" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id");



ALTER TABLE ONLY "public"."fuel_logs"
    ADD CONSTRAINT "fuel_logs_operator_uid_fkey" FOREIGN KEY ("operator_uid") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."fuel_logs"
    ADD CONSTRAINT "fuel_logs_shift_id_fkey" FOREIGN KEY ("shift_id") REFERENCES "public"."shift_logs"("id");



ALTER TABLE ONLY "public"."handover_logs"
    ADD CONSTRAINT "handover_logs_incoming_user_id_fkey" FOREIGN KEY ("incoming_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."handover_logs"
    ADD CONSTRAINT "handover_logs_outgoing_user_id_fkey" FOREIGN KEY ("outgoing_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."handover_logs"
    ADD CONSTRAINT "handover_logs_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id");



ALTER TABLE ONLY "public"."haul_cycles"
    ADD CONSTRAINT "haul_cycles_asset_id_fkey" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id");



ALTER TABLE ONLY "public"."haul_cycles"
    ADD CONSTRAINT "haul_cycles_material_id_fkey" FOREIGN KEY ("material_id") REFERENCES "public"."materials"("id");



ALTER TABLE ONLY "public"."haul_cycles"
    ADD CONSTRAINT "haul_cycles_operator_uid_fkey" FOREIGN KEY ("operator_uid") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."haul_cycles"
    ADD CONSTRAINT "haul_cycles_project_site_id_fkey" FOREIGN KEY ("project_site_id") REFERENCES "public"."project_sites"("id");



ALTER TABLE ONLY "public"."haul_cycles"
    ADD CONSTRAINT "haul_cycles_route_id_fkey" FOREIGN KEY ("route_id") REFERENCES "public"."routes"("id");



ALTER TABLE ONLY "public"."haul_cycles"
    ADD CONSTRAINT "haul_cycles_shift_id_fkey" FOREIGN KEY ("shift_id") REFERENCES "public"."shift_logs"("id");



ALTER TABLE ONLY "public"."jit_active_queues"
    ADD CONSTRAINT "jit_active_queues_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."load_cycles"
    ADD CONSTRAINT "load_cycles_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."load_cycles"
    ADD CONSTRAINT "load_cycles_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."load_cycles"
    ADD CONSTRAINT "load_cycles_reconciled_by_fkey" FOREIGN KEY ("reconciled_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."load_cycles"
    ADD CONSTRAINT "load_cycles_weighbridge_operator_id_fkey" FOREIGN KEY ("weighbridge_operator_id") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."load_offers"
    ADD CONSTRAINT "load_offers_anomaly_resolved_by_fkey" FOREIGN KEY ("anomaly_resolved_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."load_offers"
    ADD CONSTRAINT "load_offers_bypassed_by_fkey" FOREIGN KEY ("bypassed_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."load_offers"
    ADD CONSTRAINT "load_offers_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."load_offers"
    ADD CONSTRAINT "load_offers_master_order_id_fkey" FOREIGN KEY ("master_order_id") REFERENCES "public"."master_orders"("id");



ALTER TABLE ONLY "public"."master_orders"
    ADD CONSTRAINT "master_orders_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."ocr_audit_logs"
    ADD CONSTRAINT "ocr_audit_logs_override_id_fkey" FOREIGN KEY ("override_id") REFERENCES "public"."whs_overrides"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."plant_defects"
    ADD CONSTRAINT "plant_defects_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."plant_defects"
    ADD CONSTRAINT "plant_defects_rectified_by_fkey" FOREIGN KEY ("rectified_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."plant_defects"
    ADD CONSTRAINT "plant_defects_reported_by_fkey" FOREIGN KEY ("reported_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."prestart_checks"
    ADD CONSTRAINT "prestart_checks_assignment_id_fkey" FOREIGN KEY ("assignment_id") REFERENCES "public"."asset_assignments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prestart_checks"
    ADD CONSTRAINT "prestart_checks_operator_id_fkey" FOREIGN KEY ("operator_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_sites"
    ADD CONSTRAINT "project_sites_fleet_id_fkey" FOREIGN KEY ("fleet_id") REFERENCES "public"."fleets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."role_audit_logs"
    ADD CONSTRAINT "role_audit_logs_granted_by_user_id_fkey" FOREIGN KEY ("granted_by_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."role_audit_logs"
    ADD CONSTRAINT "role_audit_logs_target_user_id_fkey" FOREIGN KEY ("target_user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."shift_assignments"
    ADD CONSTRAINT "shift_assignments_assigned_by_fkey" FOREIGN KEY ("assigned_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."shift_assignments"
    ADD CONSTRAINT "shift_assignments_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."shift_assignments"
    ADD CONSTRAINT "shift_assignments_master_order_id_fkey" FOREIGN KEY ("master_order_id") REFERENCES "public"."master_orders"("id");



ALTER TABLE ONLY "public"."shift_logs"
    ADD CONSTRAINT "shift_logs_asset_id_fkey" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id");



ALTER TABLE ONLY "public"."shift_logs"
    ADD CONSTRAINT "shift_logs_operator_uid_fkey" FOREIGN KEY ("operator_uid") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."structural_elements"
    ADD CONSTRAINT "structural_elements_load_offer_id_fkey" FOREIGN KEY ("load_offer_id") REFERENCES "public"."load_offers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."system_audit_logs"
    ADD CONSTRAINT "system_audit_logs_actor_uid_fkey" FOREIGN KEY ("actor_uid") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."telemetry_inbox"
    ADD CONSTRAINT "telemetry_inbox_recorded_by_fkey" FOREIGN KEY ("recorded_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."telemetry_logs"
    ADD CONSTRAINT "telemetry_logs_asset_id_fkey" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vehicles"
    ADD CONSTRAINT "vehicles_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."webhook_endpoints"
    ADD CONSTRAINT "webhook_endpoints_fleet_id_fkey" FOREIGN KEY ("fleet_id") REFERENCES "public"."fleets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."whs_overrides"
    ADD CONSTRAINT "whs_overrides_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."whs_overrides"
    ADD CONSTRAINT "whs_overrides_supervisor_id_fkey" FOREIGN KEY ("supervisor_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."whs_prestart_logs"
    ADD CONSTRAINT "whs_prestart_logs_asset_id_fkey" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id");



ALTER TABLE ONLY "public"."whs_prestart_logs"
    ADD CONSTRAINT "whs_prestart_logs_operator_uid_fkey" FOREIGN KEY ("operator_uid") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."whs_prestart_logs"
    ADD CONSTRAINT "whs_prestart_logs_project_site_id_fkey" FOREIGN KEY ("project_site_id") REFERENCES "public"."project_sites"("id");



ALTER TABLE ONLY "public"."whs_prestarts"
    ADD CONSTRAINT "whs_prestarts_asset_id_fkey" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id");



ALTER TABLE ONLY "public"."whs_prestarts"
    ADD CONSTRAINT "whs_prestarts_operator_id_fkey" FOREIGN KEY ("operator_id") REFERENCES "public"."profiles"("id");



CREATE POLICY "Administradores pueden gestionar vehículos" ON "public"."vehicles" USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND (("profiles"."role")::"text" = ANY ((ARRAY['ADMIN'::character varying, 'FLEET_MANAGER'::character varying])::"text"[]))))));



CREATE POLICY "Allow Service Role Ingestion" ON "public"."telemetry_logs" FOR INSERT WITH CHECK (((("current_setting"('request.jwt.claims'::"text", true))::"jsonb" ->> 'role'::"text") = 'service_role'::"text"));



CREATE POLICY "Allow admin updates on system_config" ON "public"."system_config" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND (("profiles"."role")::"text" = ANY ((ARRAY['FLEET_MANAGER'::character varying, 'SUPER_ADMIN'::character varying])::"text"[]))))));



CREATE POLICY "Allow authenticated reads on system_config" ON "public"."system_config" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Allow driver to see own assignments" ON "public"."assignments" FOR SELECT TO "authenticated" USING (("operator_id" = "auth"."uid"()));



CREATE POLICY "Allow fleet manager to assign" ON "public"."assignments" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND (("profiles"."role")::"text" = ANY ((ARRAY['FLEET_MANAGER'::character varying, 'SUPER_ADMIN'::character varying])::"text"[]))))));



CREATE POLICY "Builders can create master orders" ON "public"."master_orders" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND (("profiles"."role")::"text" = ANY ((ARRAY['BUILDER'::character varying, 'SUPER_ADMIN'::character varying])::"text"[]))))));



CREATE POLICY "Builders can update master orders" ON "public"."master_orders" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND (("profiles"."role")::"text" = ANY ((ARRAY['BUILDER'::character varying, 'SUPER_ADMIN'::character varying])::"text"[]))))));



CREATE POLICY "Conductores pueden ver sus propios vehículos" ON "public"."vehicles" FOR SELECT USING (("auth"."uid"() = "profile_id"));



CREATE POLICY "Crew can view their own project cycles" ON "public"."load_cycles" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."project_members"
  WHERE (("project_members"."project_id" = "load_cycles"."project_id") AND ("project_members"."user_id" = "auth"."uid"())))));



CREATE POLICY "Cualquiera puede ver defectos" ON "public"."plant_defects" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Enforce JWT Financial Lockdown on Assets" ON "public"."assets" USING ((("fleet_id" = ((("current_setting"('request.jwt.claims'::"text", true))::"jsonb" ->> 'fleet_id'::"text"))::"uuid") AND ((("current_setting"('request.jwt.claims'::"text", true))::"jsonb" ->> 'subscription_status'::"text") = ANY (ARRAY['active'::"text", 'trialing'::"text"]))));



CREATE POLICY "Enforce JWT Financial Lockdown on Dispatch" ON "public"."asset_assignments" USING ((("fleet_id" = ((("current_setting"('request.jwt.claims'::"text", true))::"jsonb" ->> 'fleet_id'::"text"))::"uuid") AND ((("current_setting"('request.jwt.claims'::"text", true))::"jsonb" ->> 'subscription_status'::"text") = ANY (ARRAY['active'::"text", 'trialing'::"text"])) AND (((("current_setting"('request.jwt.claims'::"text", true))::"jsonb" ->> 'user_role'::"text") <> ALL (ARRAY['supervisor'::"text", 'fleet_manager'::"text", 'fitter'::"text"])) OR (("auth"."jwt"() ->> 'aal'::"text") = 'aal2'::"text"))));



CREATE POLICY "Enforce JWT Lockdown on Webhooks" ON "public"."webhook_endpoints" USING (("fleet_id" = ((("current_setting"('request.jwt.claims'::"text", true))::"jsonb" ->> 'fleet_id'::"text"))::"uuid"));



CREATE POLICY "Enforce Solvency on Hauls" ON "public"."haul_cycles" FOR INSERT TO "authenticated" WITH CHECK ("public"."fn_fleet_can_operate"());



CREATE POLICY "Enforce Solvency on Prestarts" ON "public"."whs_prestart_logs" FOR INSERT TO "authenticated" WITH CHECK ("public"."fn_fleet_can_operate"());



CREATE POLICY "Everyone can view master orders" ON "public"."master_orders" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Everyone can view shift assignments" ON "public"."shift_assignments" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Fleet Managers pueden crear invitaciones" ON "public"."fleet_invites" FOR INSERT WITH CHECK ((("auth"."uid"() = "created_by") AND ("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))));



CREATE POLICY "Fleet Managers pueden ver sus invitaciones" ON "public"."fleet_invites" FOR SELECT USING (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Fleet managers can create shift assignments" ON "public"."shift_assignments" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND (("profiles"."role")::"text" = ANY ((ARRAY['FLEET_MANAGER'::character varying, 'SUPER_ADMIN'::character varying])::"text"[]))))));



CREATE POLICY "Fleet managers can update shift assignments" ON "public"."shift_assignments" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND (("profiles"."role")::"text" = ANY ((ARRAY['FLEET_MANAGER'::character varying, 'SUPER_ADMIN'::character varying])::"text"[]))))));



CREATE POLICY "Fleet managers pueden ver todos los prestarts" ON "public"."whs_prestarts" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND (("profiles"."role")::"text" = ANY ((ARRAY['fleet_manager'::character varying, 'super_admin'::character varying])::"text"[]))))));



CREATE POLICY "HQ_global_mutate_projects" ON "public"."projects" USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND (("profiles"."role")::"text" = ANY ((ARRAY['super_admin'::character varying, 'fleet_manager'::character varying])::"text"[]))))));



CREATE POLICY "HQ_global_select_profiles" ON "public"."profiles" FOR SELECT USING (("public"."get_auth_user_role"() = ANY (ARRAY['super_admin'::"text", 'fleet_manager'::"text"])));



CREATE POLICY "HQ_global_select_projects" ON "public"."projects" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND (("profiles"."role")::"text" = ANY ((ARRAY['super_admin'::character varying, 'fleet_manager'::character varying])::"text"[]))))));



CREATE POLICY "HQ_global_update_profiles" ON "public"."profiles" FOR UPDATE USING (("public"."get_auth_user_role"() = ANY (ARRAY['super_admin'::"text", 'fleet_manager'::"text"])));



CREATE POLICY "Insert own fatigue logs" ON "public"."fatigue_logs" FOR INSERT WITH CHECK (("fleet_id" = ( SELECT "profiles"."fleet_id"
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



CREATE POLICY "Only super_admin can update fleets" ON "public"."fleets" FOR UPDATE USING (("public"."get_auth_user_role"() = 'super_admin'::"text"));



CREATE POLICY "Operarios pueden insertar sus propios prestarts" ON "public"."whs_prestarts" FOR INSERT TO "authenticated" WITH CHECK (("operator_id" = "auth"."uid"()));



CREATE POLICY "Operators can insert incidents" ON "public"."cor_incidents" FOR INSERT WITH CHECK (("operator_id" = "auth"."uid"()));



CREATE POLICY "Operators can view incidents of their loads" ON "public"."cor_incidents" FOR SELECT USING ((("operator_id" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND (("profiles"."role")::"text" = 'admin'::"text"))))));



CREATE POLICY "Public read for fleet orchestration" ON "public"."excavator_states" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "RLS_Profiles_Read_Jurisdiction" ON "public"."profiles" FOR SELECT TO "authenticated" USING ((("auth"."uid"() = "id") OR (("public"."get_auth_user_role"() = ANY (ARRAY['supervisor'::"text", 'fleet_manager'::"text", 'super_admin'::"text"])) AND ("fleet_id" = "public"."get_auth_user_fleet_id"())) OR ("public"."get_auth_user_role"() = 'super_admin'::"text")));



CREATE POLICY "RLS_Profiles_Update_Self" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Solo heavy_mechanic puede rectificar defectos" ON "public"."plant_defects" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND (("profiles"."role")::"text" = 'heavy_mechanic'::"text"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND (("profiles"."role")::"text" = 'heavy_mechanic'::"text")))));



CREATE POLICY "SuperAdmins and Fleet Managers can view billing ledger" ON "public"."billing_ledger" FOR SELECT USING (("auth"."uid"() IN ( SELECT "profiles"."id"
   FROM "public"."profiles"
  WHERE (("profiles"."role")::"text" = ANY ((ARRAY['super_admin'::character varying, 'fleet_manager'::character varying])::"text"[])))));



CREATE POLICY "SuperAdmins and Fleet Managers can view their volumetrics" ON "public"."fleet_billing_ledger" FOR SELECT USING (("auth"."uid"() IN ( SELECT "profiles"."id"
   FROM "public"."profiles"
  WHERE (("profiles"."role")::"text" = ANY ((ARRAY['super_admin'::character varying, 'fleet_manager'::character varying])::"text"[])))));



CREATE POLICY "SuperAdmins view all audit logs" ON "public"."system_audit_logs" FOR SELECT USING (((("current_setting"('request.jwt.claims'::"text", true))::"jsonb" ->> 'user_role'::"text") = 'super_admin'::"text"));



CREATE POLICY "Supervisors can view prestarts" ON "public"."prestart_checks" FOR SELECT USING (((("current_setting"('request.jwt.claims'::"text", true))::"jsonb" ->> 'user_role'::"text") = ANY (ARRAY['supervisor'::"text", 'fleet_manager'::"text", 'super_admin'::"text"])));



CREATE POLICY "Update own fleet trips" ON "public"."trips" FOR UPDATE USING (("fleet_id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Users can read own profile" ON "public"."profiles" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can view their own fleet details" ON "public"."fleets" FOR SELECT USING ((("id" = ( SELECT "profiles"."fleet_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) OR ("public"."get_auth_user_role"() = 'super_admin'::"text")));



CREATE POLICY "Usuarios pueden reportar defectos" ON "public"."plant_defects" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "reported_by"));



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



CREATE POLICY "Weighbridge operators can update active dockets" ON "public"."load_cycles" FOR UPDATE TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND (("profiles"."role")::"text" = 'weighbridge_operator'::"text")))) AND ("status" = 'in_transit'::"public"."cycle_status"))) WITH CHECK (("status" = ANY (ARRAY['dumped'::"public"."cycle_status", 'reconciled'::"public"."cycle_status"])));



CREATE POLICY "Workshop personnel can update logs" ON "public"."asset_lockouts" FOR UPDATE USING ((((("current_setting"('request.jwt.claims'::"text", true))::"jsonb" ->> 'user_role'::"text") = ANY (ARRAY['fitter'::"text", 'fleet_manager'::"text", 'super_admin'::"text"])) AND (("auth"."jwt"() ->> 'aal'::"text") = 'aal2'::"text")));



ALTER TABLE "public"."access_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "admin_view_logs" ON "public"."access_logs" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND (("profiles"."role")::"text" = 'admin'::"text")))));



ALTER TABLE "public"."asset_assignments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."asset_lockouts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."asset_telemetry_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."assets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."assignments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_contracts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_ledger" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."clients" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."compliance_documents" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cor_incidents" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cor_manifests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "dlq_super_admin_select_policy" ON "public"."telemetry_dead_letter_logs" FOR SELECT USING (((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = 'super_admin'::"text"));



ALTER TABLE "public"."excavator_states" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."execution_certificates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."expenses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."fatigue_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."fleet_billing_ledger" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."fleet_invites" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."fleets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."fuel_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."haul_cycles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."invoices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."jit_active_queues" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."load_cycles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."load_offers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."maintenance_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."maintenance_schedules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."master_orders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."materials" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nhvr_compliance_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nodes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ocr_audit_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "operator_insert_manifest" ON "public"."cor_manifests" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."assignments"
  WHERE (("assignments"."load_offer_id" = "cor_manifests"."load_offer_id") AND ("assignments"."operator_id" = "auth"."uid"())))));



CREATE POLICY "operator_insert_telemetry_inbox" ON "public"."telemetry_inbox" FOR INSERT WITH CHECK (("auth"."uid"() = "recorded_by"));



CREATE POLICY "operator_view_policy" ON "public"."load_offers" FOR SELECT USING ((((("status")::"text" = 'BIDDING_OPEN'::"text") AND "public"."matches_contractor_profile"("auth"."uid"(), "id")) OR ("id" IN ( SELECT "assignments"."load_offer_id"
   FROM "public"."assignments"
  WHERE ("assignments"."operator_id" = "auth"."uid"())))));



ALTER TABLE "public"."plant_defects" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."prestart_checks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "project_access_policy" ON "public"."projects" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."project_members"
  WHERE (("project_members"."project_id" = "projects"."id") AND ("project_members"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."project_sites" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."projects" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "rls_asset_lockouts_select_policy" ON "public"."asset_lockouts" FOR SELECT USING (("fleet_id" = "public"."fn_get_caller_fleet_id"()));



CREATE POLICY "rls_assets_select_policy" ON "public"."assets" FOR SELECT USING (("fleet_id" = "public"."fn_get_caller_fleet_id"()));



CREATE POLICY "rls_fuel_logs_select_policy" ON "public"."fuel_logs" FOR SELECT USING (("fleet_id" = "public"."fn_get_caller_fleet_id"()));



CREATE POLICY "rls_haul_cycles_select_policy" ON "public"."haul_cycles" FOR SELECT USING (("fleet_id" = "public"."fn_get_caller_fleet_id"()));



CREATE POLICY "rls_materials_select_policy" ON "public"."materials" FOR SELECT USING (("fleet_id" = "public"."fn_get_caller_fleet_id"()));



CREATE POLICY "rls_profiles_select_policy" ON "public"."profiles" FOR SELECT USING ((("id" = "auth"."uid"()) OR ("fleet_id" = "public"."fn_get_caller_fleet_id"())));



CREATE POLICY "rls_routes_select_policy" ON "public"."routes" FOR SELECT USING (("fleet_id" = "public"."fn_get_caller_fleet_id"()));



CREATE POLICY "rls_shift_logs_select_policy" ON "public"."shift_logs" FOR SELECT USING (("fleet_id" = "public"."fn_get_caller_fleet_id"()));



CREATE POLICY "rls_whs_prestart_logs_select_policy" ON "public"."whs_prestart_logs" FOR SELECT USING (("fleet_id" = "public"."fn_get_caller_fleet_id"()));



ALTER TABLE "public"."role_audit_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "role_audit_logs_read_policy" ON "public"."role_audit_logs" FOR SELECT USING (((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = 'super_admin'::"text"));



ALTER TABLE "public"."routes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."service_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "service_role_insert_ocr_logs" ON "public"."ocr_audit_logs" FOR INSERT WITH CHECK ((("current_setting"('role'::"text") = 'service_role'::"text") OR ("current_setting"('role'::"text") = 'postgres'::"text")));



ALTER TABLE "public"."shift_assignments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shift_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sos_alerts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."system_audit_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."system_config" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."telemetry_dead_letter_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."telemetry_inbox" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "telemetry_insert_policy" ON "public"."asset_telemetry_logs" FOR INSERT WITH CHECK (("auth"."uid"() = "recorded_by"));



ALTER TABLE "public"."telemetry_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."trip_waypoints" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."trips" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."vehicles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "view_ocr_logs" ON "public"."ocr_audit_logs" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND (("profiles"."role")::"text" = ANY ((ARRAY['super_admin'::character varying, 'fleet_manager'::character varying])::"text"[]))))));



CREATE POLICY "view_own_docs" ON "public"."compliance_documents" USING (("profile_id" = "auth"."uid"()));



ALTER TABLE "public"."webhook_endpoints" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."webhook_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."whs_overrides" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."whs_prestart_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."whs_prestarts" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."handover_logs";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."projects";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."webhook_events";






GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






GRANT ALL ON FUNCTION "public"."box2d_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."box2d_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."box2d_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2d_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."box2d_out"("public"."box2d") TO "postgres";
GRANT ALL ON FUNCTION "public"."box2d_out"("public"."box2d") TO "anon";
GRANT ALL ON FUNCTION "public"."box2d_out"("public"."box2d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2d_out"("public"."box2d") TO "service_role";



GRANT ALL ON FUNCTION "public"."box2df_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."box2df_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."box2df_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2df_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."box2df_out"("public"."box2df") TO "postgres";
GRANT ALL ON FUNCTION "public"."box2df_out"("public"."box2df") TO "anon";
GRANT ALL ON FUNCTION "public"."box2df_out"("public"."box2df") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2df_out"("public"."box2df") TO "service_role";



GRANT ALL ON FUNCTION "public"."box3d_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."box3d_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."box3d_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box3d_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."box3d_out"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."box3d_out"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."box3d_out"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box3d_out"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_out"("public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_out"("public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_out"("public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_out"("public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_recv"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_recv"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_recv"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_recv"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_send"("public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_send"("public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_send"("public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_send"("public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey16_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey16_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey16_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey16_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey16_out"("public"."gbtreekey16") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey16_out"("public"."gbtreekey16") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey16_out"("public"."gbtreekey16") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey16_out"("public"."gbtreekey16") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey2_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey2_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey2_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey2_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey2_out"("public"."gbtreekey2") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey2_out"("public"."gbtreekey2") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey2_out"("public"."gbtreekey2") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey2_out"("public"."gbtreekey2") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey32_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey32_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey32_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey32_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey32_out"("public"."gbtreekey32") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey32_out"("public"."gbtreekey32") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey32_out"("public"."gbtreekey32") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey32_out"("public"."gbtreekey32") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey4_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey4_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey4_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey4_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey4_out"("public"."gbtreekey4") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey4_out"("public"."gbtreekey4") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey4_out"("public"."gbtreekey4") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey4_out"("public"."gbtreekey4") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey8_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey8_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey8_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey8_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey8_out"("public"."gbtreekey8") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey8_out"("public"."gbtreekey8") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey8_out"("public"."gbtreekey8") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey8_out"("public"."gbtreekey8") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey_var_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbtreekey_var_out"("public"."gbtreekey_var") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_out"("public"."gbtreekey_var") TO "anon";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_out"("public"."gbtreekey_var") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbtreekey_var_out"("public"."gbtreekey_var") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_analyze"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_analyze"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_analyze"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_analyze"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_out"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_out"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_out"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_out"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_send"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_send"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_send"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_send"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_typmod_out"(integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_typmod_out"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_typmod_out"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_typmod_out"(integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_analyze"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_analyze"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_analyze"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_analyze"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_out"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_out"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_out"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_out"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_recv"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_recv"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_recv"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_recv"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_send"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_send"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_send"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_send"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_typmod_out"(integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_typmod_out"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_typmod_out"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_typmod_out"(integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."gidx_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gidx_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gidx_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gidx_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gidx_out"("public"."gidx") TO "postgres";
GRANT ALL ON FUNCTION "public"."gidx_out"("public"."gidx") TO "anon";
GRANT ALL ON FUNCTION "public"."gidx_out"("public"."gidx") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gidx_out"("public"."gidx") TO "service_role";



GRANT ALL ON FUNCTION "public"."spheroid_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."spheroid_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."spheroid_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."spheroid_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."spheroid_out"("public"."spheroid") TO "postgres";
GRANT ALL ON FUNCTION "public"."spheroid_out"("public"."spheroid") TO "anon";
GRANT ALL ON FUNCTION "public"."spheroid_out"("public"."spheroid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."spheroid_out"("public"."spheroid") TO "service_role";



GRANT ALL ON FUNCTION "public"."box3d"("public"."box2d") TO "postgres";
GRANT ALL ON FUNCTION "public"."box3d"("public"."box2d") TO "anon";
GRANT ALL ON FUNCTION "public"."box3d"("public"."box2d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box3d"("public"."box2d") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("public"."box2d") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("public"."box2d") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("public"."box2d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("public"."box2d") TO "service_role";



GRANT ALL ON FUNCTION "public"."box"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."box"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."box"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."box2d"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."box2d"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."box2d"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2d"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."geography"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."bytea"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."bytea"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."bytea"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bytea"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography"("public"."geography", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."geography"("public"."geography", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."geography"("public"."geography", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography"("public"."geography", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."box"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."box"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."box"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."box2d"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."box2d"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."box2d"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box2d"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."box3d"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."box3d"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."box3d"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box3d"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."bytea"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."bytea"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."bytea"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bytea"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geography"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("public"."geometry", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("public"."geometry", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("public"."geometry", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("public"."geometry", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."json"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."json"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."json"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."json"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."jsonb"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."jsonb"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."jsonb"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."jsonb"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."path"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."path"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."path"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."path"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."point"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."point"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."point"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."point"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."polygon"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."polygon"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."polygon"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."polygon"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."text"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."text"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."text"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."text"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("path") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("path") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("path") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("path") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("point") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("point") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("point") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("point") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("polygon") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("polygon") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("polygon") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("polygon") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry"("text") TO "service_role";











































































































































































GRANT ALL ON FUNCTION "public"."_postgis_deprecate"("oldname" "text", "newname" "text", "version" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_postgis_deprecate"("oldname" "text", "newname" "text", "version" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_deprecate"("oldname" "text", "newname" "text", "version" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_deprecate"("oldname" "text", "newname" "text", "version" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_postgis_index_extent"("tbl" "regclass", "col" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_postgis_index_extent"("tbl" "regclass", "col" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_index_extent"("tbl" "regclass", "col" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_index_extent"("tbl" "regclass", "col" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_postgis_join_selectivity"("regclass", "text", "regclass", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_postgis_join_selectivity"("regclass", "text", "regclass", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_join_selectivity"("regclass", "text", "regclass", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_join_selectivity"("regclass", "text", "regclass", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_postgis_pgsql_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."_postgis_pgsql_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_pgsql_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_pgsql_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_postgis_scripts_pgsql_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."_postgis_scripts_pgsql_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_scripts_pgsql_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_scripts_pgsql_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_postgis_selectivity"("tbl" "regclass", "att_name" "text", "geom" "public"."geometry", "mode" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_postgis_selectivity"("tbl" "regclass", "att_name" "text", "geom" "public"."geometry", "mode" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_selectivity"("tbl" "regclass", "att_name" "text", "geom" "public"."geometry", "mode" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_selectivity"("tbl" "regclass", "att_name" "text", "geom" "public"."geometry", "mode" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_postgis_stats"("tbl" "regclass", "att_name" "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_postgis_stats"("tbl" "regclass", "att_name" "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_postgis_stats"("tbl" "regclass", "att_name" "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postgis_stats"("tbl" "regclass", "att_name" "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_3ddfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_3ddfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_3ddfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_3ddfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_3ddwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_3ddwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_3ddwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_3ddwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_3dintersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_3dintersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_3dintersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_3dintersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_asgml"(integer, "public"."geometry", integer, integer, "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_asgml"(integer, "public"."geometry", integer, integer, "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_asgml"(integer, "public"."geometry", integer, integer, "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_asgml"(integer, "public"."geometry", integer, integer, "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_asx3d"(integer, "public"."geometry", integer, integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_asx3d"(integer, "public"."geometry", integer, integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_asx3d"(integer, "public"."geometry", integer, integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_asx3d"(integer, "public"."geometry", integer, integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_bestsrid"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_bestsrid"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_bestsrid"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_bestsrid"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_bestsrid"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_bestsrid"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_bestsrid"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_bestsrid"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_containsproperly"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_containsproperly"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_containsproperly"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_containsproperly"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_coveredby"("geog1" "public"."geography", "geog2" "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_coveredby"("geog1" "public"."geography", "geog2" "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_coveredby"("geog1" "public"."geography", "geog2" "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_coveredby"("geog1" "public"."geography", "geog2" "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_coveredby"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_coveredby"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_coveredby"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_coveredby"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_covers"("geog1" "public"."geography", "geog2" "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_covers"("geog1" "public"."geography", "geog2" "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_covers"("geog1" "public"."geography", "geog2" "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_covers"("geog1" "public"."geography", "geog2" "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_covers"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_covers"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_covers"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_covers"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_crosses"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_crosses"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_crosses"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_crosses"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_dfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_dfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_dfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_dfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_distancetree"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_distancetree"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_distancetree"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_distancetree"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_distancetree"("public"."geography", "public"."geography", double precision, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_distancetree"("public"."geography", "public"."geography", double precision, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_distancetree"("public"."geography", "public"."geography", double precision, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_distancetree"("public"."geography", "public"."geography", double precision, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography", boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography", boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography", boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography", boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography", double precision, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography", double precision, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography", double precision, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_distanceuncached"("public"."geography", "public"."geography", double precision, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_dwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_dwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_dwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_dwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_dwithin"("geog1" "public"."geography", "geog2" "public"."geography", "tolerance" double precision, "use_spheroid" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_dwithin"("geog1" "public"."geography", "geog2" "public"."geography", "tolerance" double precision, "use_spheroid" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_dwithin"("geog1" "public"."geography", "geog2" "public"."geography", "tolerance" double precision, "use_spheroid" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_dwithin"("geog1" "public"."geography", "geog2" "public"."geography", "tolerance" double precision, "use_spheroid" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"("public"."geography", "public"."geography", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"("public"."geography", "public"."geography", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"("public"."geography", "public"."geography", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"("public"."geography", "public"."geography", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"("public"."geography", "public"."geography", double precision, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"("public"."geography", "public"."geography", double precision, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"("public"."geography", "public"."geography", double precision, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_dwithinuncached"("public"."geography", "public"."geography", double precision, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_expand"("public"."geography", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_expand"("public"."geography", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_expand"("public"."geography", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_expand"("public"."geography", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_geomfromgml"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_geomfromgml"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_geomfromgml"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_geomfromgml"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_intersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_intersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_intersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_intersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_linecrossingdirection"("line1" "public"."geometry", "line2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_linecrossingdirection"("line1" "public"."geometry", "line2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_linecrossingdirection"("line1" "public"."geometry", "line2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_linecrossingdirection"("line1" "public"."geometry", "line2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_longestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_longestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_longestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_longestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_maxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_maxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_maxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_maxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_orderingequals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_orderingequals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_orderingequals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_orderingequals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_pointoutside"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_pointoutside"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_pointoutside"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_pointoutside"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_sortablehash"("geom" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_sortablehash"("geom" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_sortablehash"("geom" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_sortablehash"("geom" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_touches"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_touches"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_touches"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_touches"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_voronoi"("g1" "public"."geometry", "clip" "public"."geometry", "tolerance" double precision, "return_polygons" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_voronoi"("g1" "public"."geometry", "clip" "public"."geometry", "tolerance" double precision, "return_polygons" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."_st_voronoi"("g1" "public"."geometry", "clip" "public"."geometry", "tolerance" double precision, "return_polygons" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_voronoi"("g1" "public"."geometry", "clip" "public"."geometry", "tolerance" double precision, "return_polygons" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."_st_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."_st_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."_st_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_st_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON TABLE "public"."load_offers" TO "anon";
GRANT ALL ON TABLE "public"."load_offers" TO "authenticated";
GRANT ALL ON TABLE "public"."load_offers" TO "service_role";



GRANT ALL ON FUNCTION "public"."active_excavation_geojson"("offer" "public"."load_offers") TO "anon";
GRANT ALL ON FUNCTION "public"."active_excavation_geojson"("offer" "public"."load_offers") TO "authenticated";
GRANT ALL ON FUNCTION "public"."active_excavation_geojson"("offer" "public"."load_offers") TO "service_role";



GRANT ALL ON FUNCTION "public"."addauth"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."addauth"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."addauth"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."addauth"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("table_name" character varying, "column_name" character varying, "new_srid" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("table_name" character varying, "column_name" character varying, "new_srid" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("table_name" character varying, "column_name" character varying, "new_srid" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("table_name" character varying, "column_name" character varying, "new_srid" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid_in" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid_in" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid_in" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."addgeometrycolumn"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid_in" integer, "new_type" character varying, "new_dim" integer, "use_typmod" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."audit_log_changes"() TO "anon";
GRANT ALL ON FUNCTION "public"."audit_log_changes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."audit_log_changes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."audit_the_ocr_auditor"() TO "anon";
GRANT ALL ON FUNCTION "public"."audit_the_ocr_auditor"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."audit_the_ocr_auditor"() TO "service_role";



GRANT ALL ON FUNCTION "public"."box3dtobox"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."box3dtobox"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."box3dtobox"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."box3dtobox"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_buffered_loading_pad"() TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_buffered_loading_pad"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_buffered_loading_pad"() TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_fleet_health_scores"("p_fleet_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_fleet_health_scores"("p_fleet_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_fleet_health_scores"("p_fleet_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."cash_dist"("money", "money") TO "postgres";
GRANT ALL ON FUNCTION "public"."cash_dist"("money", "money") TO "anon";
GRANT ALL ON FUNCTION "public"."cash_dist"("money", "money") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cash_dist"("money", "money") TO "service_role";



GRANT ALL ON FUNCTION "public"."certify_prestart"("p_assignment_id" "uuid", "p_brakes" boolean, "p_fluids" boolean, "p_structural" boolean, "p_is_safe" boolean, "p_defect_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."certify_prestart"("p_assignment_id" "uuid", "p_brakes" boolean, "p_fluids" boolean, "p_structural" boolean, "p_is_safe" boolean, "p_defect_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."certify_prestart"("p_assignment_id" "uuid", "p_brakes" boolean, "p_fluids" boolean, "p_structural" boolean, "p_is_safe" boolean, "p_defect_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_active_defects_before_shift"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_active_defects_before_shift"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_active_defects_before_shift"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_insurance_compliance"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_insurance_compliance"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_insurance_compliance"() TO "service_role";



GRANT ALL ON FUNCTION "public"."checkauth"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."checkauth"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."checkauth"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."checkauth"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."checkauth"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."checkauth"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."checkauth"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."checkauth"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."checkauthtrigger"() TO "postgres";
GRANT ALL ON FUNCTION "public"."checkauthtrigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."checkauthtrigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."checkauthtrigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."close_active_shift"("p_assignment_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."close_active_shift"("p_assignment_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."close_active_shift"("p_assignment_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."contains_2d"("public"."box2df", "public"."box2df") TO "postgres";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."box2df", "public"."box2df") TO "anon";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."box2df", "public"."box2df") TO "authenticated";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."box2df", "public"."box2df") TO "service_role";



GRANT ALL ON FUNCTION "public"."contains_2d"("public"."box2df", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."box2df", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."box2df", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."box2df", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."contains_2d"("public"."geometry", "public"."box2df") TO "postgres";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."geometry", "public"."box2df") TO "anon";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."geometry", "public"."box2df") TO "authenticated";
GRANT ALL ON FUNCTION "public"."contains_2d"("public"."geometry", "public"."box2df") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"(double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube"(double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"(double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"(double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"(double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube"(double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"(double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"(double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"(double precision[], double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube"(double precision[], double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"(double precision[], double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"(double precision[], double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"(double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube"(double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"(double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"(double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_cmp"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_cmp"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_cmp"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_cmp"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_contained"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_contained"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_contained"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_contained"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_contains"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_contains"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_contains"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_contains"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_coord"("public"."cube", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_coord"("public"."cube", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_coord"("public"."cube", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_coord"("public"."cube", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_coord_llur"("public"."cube", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_coord_llur"("public"."cube", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_coord_llur"("public"."cube", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_coord_llur"("public"."cube", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_dim"("public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_dim"("public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_dim"("public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_dim"("public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_distance"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_distance"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_distance"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_distance"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_enlarge"("public"."cube", double precision, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_enlarge"("public"."cube", double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_enlarge"("public"."cube", double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_enlarge"("public"."cube", double precision, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_eq"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_eq"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_eq"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_eq"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_ge"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_ge"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_ge"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_ge"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_gt"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_gt"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_gt"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_gt"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_inter"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_inter"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_inter"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_inter"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_is_point"("public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_is_point"("public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_is_point"("public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_is_point"("public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_le"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_le"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_le"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_le"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_ll_coord"("public"."cube", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_ll_coord"("public"."cube", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_ll_coord"("public"."cube", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_ll_coord"("public"."cube", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_lt"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_lt"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_lt"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_lt"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_ne"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_ne"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_ne"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_ne"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_overlap"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_overlap"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_overlap"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_overlap"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_size"("public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_size"("public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_size"("public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_size"("public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_subset"("public"."cube", integer[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_subset"("public"."cube", integer[]) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_subset"("public"."cube", integer[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_subset"("public"."cube", integer[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_union"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_union"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_union"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_union"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_ur_coord"("public"."cube", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_ur_coord"("public"."cube", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_ur_coord"("public"."cube", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_ur_coord"("public"."cube", integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."custom_access_token_hook"("event" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."custom_access_token_hook"("event" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."custom_access_token_hook"("event" "jsonb") TO "supabase_auth_admin";



GRANT ALL ON FUNCTION "public"."date_dist"("date", "date") TO "postgres";
GRANT ALL ON FUNCTION "public"."date_dist"("date", "date") TO "anon";
GRANT ALL ON FUNCTION "public"."date_dist"("date", "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."date_dist"("date", "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."disablelongtransactions"() TO "postgres";
GRANT ALL ON FUNCTION "public"."disablelongtransactions"() TO "anon";
GRANT ALL ON FUNCTION "public"."disablelongtransactions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."disablelongtransactions"() TO "service_role";



GRANT ALL ON FUNCTION "public"."distance_chebyshev"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."distance_chebyshev"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."distance_chebyshev"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."distance_chebyshev"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."distance_taxicab"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."distance_taxicab"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."distance_taxicab"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."distance_taxicab"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("table_name" character varying, "column_name" character varying) TO "postgres";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("table_name" character varying, "column_name" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("table_name" character varying, "column_name" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("table_name" character varying, "column_name" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("schema_name" character varying, "table_name" character varying, "column_name" character varying) TO "postgres";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("schema_name" character varying, "table_name" character varying, "column_name" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("schema_name" character varying, "table_name" character varying, "column_name" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("schema_name" character varying, "table_name" character varying, "column_name" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying) TO "postgres";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrycolumn"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."dropgeometrytable"("table_name" character varying) TO "postgres";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("table_name" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("table_name" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("table_name" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."dropgeometrytable"("schema_name" character varying, "table_name" character varying) TO "postgres";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("schema_name" character varying, "table_name" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("schema_name" character varying, "table_name" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("schema_name" character varying, "table_name" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."dropgeometrytable"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying) TO "postgres";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."dropgeometrytable"("catalog_name" character varying, "schema_name" character varying, "table_name" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."earth"() TO "postgres";
GRANT ALL ON FUNCTION "public"."earth"() TO "anon";
GRANT ALL ON FUNCTION "public"."earth"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."earth"() TO "service_role";



GRANT ALL ON FUNCTION "public"."gc_to_sec"(double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."gc_to_sec"(double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."gc_to_sec"(double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gc_to_sec"(double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."earth_box"("public"."earth", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."earth_box"("public"."earth", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."earth_box"("public"."earth", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."earth_box"("public"."earth", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."sec_to_gc"(double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."sec_to_gc"(double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."sec_to_gc"(double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sec_to_gc"(double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."earth_distance"("public"."earth", "public"."earth") TO "postgres";
GRANT ALL ON FUNCTION "public"."earth_distance"("public"."earth", "public"."earth") TO "anon";
GRANT ALL ON FUNCTION "public"."earth_distance"("public"."earth", "public"."earth") TO "authenticated";
GRANT ALL ON FUNCTION "public"."earth_distance"("public"."earth", "public"."earth") TO "service_role";



GRANT ALL ON FUNCTION "public"."emergency_reset_mfa"("p_target_uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."emergency_reset_mfa"("p_target_uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."emergency_reset_mfa"("p_target_uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."enablelongtransactions"() TO "postgres";
GRANT ALL ON FUNCTION "public"."enablelongtransactions"() TO "anon";
GRANT ALL ON FUNCTION "public"."enablelongtransactions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."enablelongtransactions"() TO "service_role";



GRANT ALL ON FUNCTION "public"."equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."exclusion_zone_geojson"("offer" "public"."load_offers") TO "anon";
GRANT ALL ON FUNCTION "public"."exclusion_zone_geojson"("offer" "public"."load_offers") TO "authenticated";
GRANT ALL ON FUNCTION "public"."exclusion_zone_geojson"("offer" "public"."load_offers") TO "service_role";



GRANT ALL ON FUNCTION "public"."execute_instant_revocation"("p_target_uid" "uuid", "p_forensic_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."execute_instant_revocation"("p_target_uid" "uuid", "p_forensic_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."execute_instant_revocation"("p_target_uid" "uuid", "p_forensic_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."find_srid"(character varying, character varying, character varying) TO "postgres";
GRANT ALL ON FUNCTION "public"."find_srid"(character varying, character varying, character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."find_srid"(character varying, character varying, character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."find_srid"(character varying, character varying, character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."float4_dist"(real, real) TO "postgres";
GRANT ALL ON FUNCTION "public"."float4_dist"(real, real) TO "anon";
GRANT ALL ON FUNCTION "public"."float4_dist"(real, real) TO "authenticated";
GRANT ALL ON FUNCTION "public"."float4_dist"(real, real) TO "service_role";



GRANT ALL ON FUNCTION "public"."float8_dist"(double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."float8_dist"(double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."float8_dist"(double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."float8_dist"(double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_assign_asset_to_project"("p_load_offer_id" "uuid", "p_driver_id" "uuid", "p_asset_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_assign_asset_to_project"("p_load_offer_id" "uuid", "p_driver_id" "uuid", "p_asset_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_assign_asset_to_project"("p_load_offer_id" "uuid", "p_driver_id" "uuid", "p_asset_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_capture_daily_fleet_usage"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_capture_daily_fleet_usage"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_capture_daily_fleet_usage"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_consume_fleet_invite"("p_token" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_consume_fleet_invite"("p_token" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_consume_fleet_invite"("p_token" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_default_project_site"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_default_project_site"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_default_project_site"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_dispatch_shift"("p_master_order_id" "uuid", "p_driver_id" "uuid", "p_asset_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_dispatch_shift"("p_master_order_id" "uuid", "p_driver_id" "uuid", "p_asset_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_dispatch_shift"("p_master_order_id" "uuid", "p_driver_id" "uuid", "p_asset_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_elevate_user_role"("p_target_id" "uuid", "p_new_role" "text", "p_justification" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_elevate_user_role"("p_target_id" "uuid", "p_new_role" "text", "p_justification" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_elevate_user_role"("p_target_id" "uuid", "p_new_role" "text", "p_justification" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_emergency_override_lockout"("p_asset_id" "uuid", "p_override_reason" character varying, "p_manager_pin" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_emergency_override_lockout"("p_asset_id" "uuid", "p_override_reason" character varying, "p_manager_pin" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_emergency_override_lockout"("p_asset_id" "uuid", "p_override_reason" character varying, "p_manager_pin" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_enforce_operator_validity"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_enforce_operator_validity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_enforce_operator_validity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_enforce_solvency_lockdown"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_enforce_solvency_lockdown"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_enforce_solvency_lockdown"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_enforce_whs_lockout"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_enforce_whs_lockout"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_enforce_whs_lockout"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_execute_haul_transition"("p_asset_id" "uuid", "p_action" character varying, "p_route_id" "uuid", "p_material_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_execute_haul_transition"("p_asset_id" "uuid", "p_action" character varying, "p_route_id" "uuid", "p_material_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_execute_haul_transition"("p_asset_id" "uuid", "p_action" character varying, "p_route_id" "uuid", "p_material_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_execute_haul_transition"("p_asset_id" "uuid", "p_action" character varying, "p_route_id" "uuid", "p_material_id" "uuid", "p_client_timestamp" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_execute_haul_transition"("p_asset_id" "uuid", "p_action" character varying, "p_route_id" "uuid", "p_material_id" "uuid", "p_client_timestamp" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_execute_haul_transition"("p_asset_id" "uuid", "p_action" character varying, "p_route_id" "uuid", "p_material_id" "uuid", "p_client_timestamp" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_execute_shift_action"("p_action" character varying, "p_asset_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_execute_shift_action"("p_action" character varying, "p_asset_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_execute_shift_action"("p_action" character varying, "p_asset_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_export_regulatory_report"("p_report_type" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_export_regulatory_report"("p_report_type" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_export_regulatory_report"("p_report_type" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_fleet_can_operate"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_fleet_can_operate"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_fleet_can_operate"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_generate_fleet_invite"("p_fleet_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_generate_fleet_invite"("p_fleet_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_generate_fleet_invite"("p_fleet_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_get_caller_fleet_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_get_caller_fleet_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_get_caller_fleet_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_guard_asset_site_transfer"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_guard_asset_site_transfer"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_guard_asset_site_transfer"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_guard_profile_privileges"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_guard_profile_privileges"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_guard_profile_privileges"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_inject_retroactive_docket"("p_master_order_id" "uuid", "p_driver_id" "uuid", "p_loaded_gross_mass" numeric, "p_paper_docket_ref" character varying, "p_docket_image_path" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_inject_retroactive_docket"("p_master_order_id" "uuid", "p_driver_id" "uuid", "p_loaded_gross_mass" numeric, "p_paper_docket_ref" character varying, "p_docket_image_path" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_inject_retroactive_docket"("p_master_order_id" "uuid", "p_driver_id" "uuid", "p_loaded_gross_mass" numeric, "p_paper_docket_ref" character varying, "p_docket_image_path" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_override_pin_lockout"("p_target_operator_uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_override_pin_lockout"("p_target_operator_uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_override_pin_lockout"("p_target_operator_uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_override_shift_assignment"("p_absent_driver_id" "uuid", "p_reserve_driver_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_override_shift_assignment"("p_absent_driver_id" "uuid", "p_reserve_driver_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_override_shift_assignment"("p_absent_driver_id" "uuid", "p_reserve_driver_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_promote_to_account_owner"("p_user_uid" "uuid", "p_fleet_name" character varying, "p_stripe_customer_id" character varying, "p_stripe_subscription_id" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_promote_to_account_owner"("p_user_uid" "uuid", "p_fleet_name" character varying, "p_stripe_customer_id" character varying, "p_stripe_subscription_id" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_promote_to_account_owner"("p_user_uid" "uuid", "p_fleet_name" character varying, "p_stripe_customer_id" character varying, "p_stripe_subscription_id" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_release_asset_lockout"("p_lockout_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_release_asset_lockout"("p_lockout_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_release_asset_lockout"("p_lockout_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_release_asset_lockout"("p_asset_id" "uuid", "p_resolution_notes" "text", "p_fitter_pin" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_release_asset_lockout"("p_asset_id" "uuid", "p_resolution_notes" "text", "p_fitter_pin" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_release_asset_lockout"("p_asset_id" "uuid", "p_resolution_notes" "text", "p_fitter_pin" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_request_detach"("p_reason" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_request_detach"("p_reason" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_request_detach"("p_reason" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_request_detach"("p_shift_id" "uuid", "p_reason" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_request_detach"("p_shift_id" "uuid", "p_reason" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_request_detach"("p_shift_id" "uuid", "p_reason" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_revoke_driver_access"("p_driver_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_revoke_driver_access"("p_driver_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_revoke_driver_access"("p_driver_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_revoke_user_role"("p_target_id" "uuid", "p_new_role" "text", "p_justification" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_revoke_user_role"("p_target_id" "uuid", "p_new_role" "text", "p_justification" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_revoke_user_role"("p_target_id" "uuid", "p_new_role" "text", "p_justification" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_set_operator_pin"("p_pin" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_set_operator_pin"("p_pin" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_set_operator_pin"("p_pin" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_simulate_payment_success"("p_fleet_id" "uuid", "p_amount_due" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_simulate_payment_success"("p_fleet_id" "uuid", "p_amount_due" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_simulate_payment_success"("p_fleet_id" "uuid", "p_amount_due" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_snapshot_daily_billing"("p_target_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_snapshot_daily_billing"("p_target_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_snapshot_daily_billing"("p_target_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_submit_fuel_log"("p_asset_id" "uuid", "p_liters_filled" numeric, "p_engine_hours" numeric, "p_cost_per_liter" numeric, "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_submit_fuel_log"("p_asset_id" "uuid", "p_liters_filled" numeric, "p_engine_hours" numeric, "p_cost_per_liter" numeric, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_submit_fuel_log"("p_asset_id" "uuid", "p_liters_filled" numeric, "p_engine_hours" numeric, "p_cost_per_liter" numeric, "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_submit_fuel_log"("p_asset_id" "uuid", "p_liters_filled" numeric, "p_engine_hours" numeric, "p_cost_per_liter" numeric, "p_location_tag" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_submit_fuel_log"("p_asset_id" "uuid", "p_liters_filled" numeric, "p_engine_hours" numeric, "p_cost_per_liter" numeric, "p_location_tag" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_submit_fuel_log"("p_asset_id" "uuid", "p_liters_filled" numeric, "p_engine_hours" numeric, "p_cost_per_liter" numeric, "p_location_tag" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_submit_whs_prestart"("p_asset_id" "uuid", "p_checklist_data" "jsonb", "p_defect_notes" "jsonb", "p_passed" boolean, "p_client_timestamp" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_submit_whs_prestart"("p_asset_id" "uuid", "p_checklist_data" "jsonb", "p_defect_notes" "jsonb", "p_passed" boolean, "p_client_timestamp" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_submit_whs_prestart"("p_asset_id" "uuid", "p_checklist_data" "jsonb", "p_defect_notes" "jsonb", "p_passed" boolean, "p_client_timestamp" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_sweep_orphan_evidence"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_sweep_orphan_evidence"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_sweep_orphan_evidence"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_trigger_autoloop"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_trigger_autoloop"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_trigger_autoloop"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_verify_driver_insurance"("p_driver_id" "uuid", "p_expiry_date" "date", "p_file_path" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_verify_driver_insurance"("p_driver_id" "uuid", "p_expiry_date" "date", "p_file_path" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_verify_driver_insurance"("p_driver_id" "uuid", "p_expiry_date" "date", "p_file_path" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_verify_operator_pin"("p_pin" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_verify_operator_pin"("p_pin" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_verify_operator_pin"("p_pin" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."force_close_shift"("p_assignment_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."force_close_shift"("p_assignment_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."force_close_shift"("p_assignment_id" "uuid", "p_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_consistent"("internal", "public"."cube", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."g_cube_consistent"("internal", "public"."cube", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_consistent"("internal", "public"."cube", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_consistent"("internal", "public"."cube", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_distance"("internal", "public"."cube", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."g_cube_distance"("internal", "public"."cube", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_distance"("internal", "public"."cube", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_distance"("internal", "public"."cube", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."g_cube_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."g_cube_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_same"("public"."cube", "public"."cube", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."g_cube_same"("public"."cube", "public"."cube", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_same"("public"."cube", "public"."cube", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_same"("public"."cube", "public"."cube", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."g_cube_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_consistent"("internal", bit, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_consistent"("internal", bit, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_consistent"("internal", bit, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_consistent"("internal", bit, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bit_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bit_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bit_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bit_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_consistent"("internal", boolean, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_consistent"("internal", boolean, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_consistent"("internal", boolean, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_consistent"("internal", boolean, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_same"("public"."gbtreekey2", "public"."gbtreekey2", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_same"("public"."gbtreekey2", "public"."gbtreekey2", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_same"("public"."gbtreekey2", "public"."gbtreekey2", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_same"("public"."gbtreekey2", "public"."gbtreekey2", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bool_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bool_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bool_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bool_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bpchar_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bpchar_consistent"("internal", character, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_consistent"("internal", character, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_consistent"("internal", character, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bpchar_consistent"("internal", character, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_consistent"("internal", "bytea", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_consistent"("internal", "bytea", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_consistent"("internal", "bytea", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_consistent"("internal", "bytea", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_bytea_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_bytea_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_bytea_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_bytea_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_consistent"("internal", "money", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_consistent"("internal", "money", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_consistent"("internal", "money", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_consistent"("internal", "money", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_distance"("internal", "money", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_distance"("internal", "money", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_distance"("internal", "money", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_distance"("internal", "money", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_cash_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_cash_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_cash_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_cash_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_consistent"("internal", "date", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_consistent"("internal", "date", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_consistent"("internal", "date", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_consistent"("internal", "date", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_distance"("internal", "date", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_distance"("internal", "date", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_distance"("internal", "date", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_distance"("internal", "date", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_date_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_date_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_date_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_date_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_decompress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_decompress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_decompress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_decompress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_consistent"("internal", "anyenum", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_consistent"("internal", "anyenum", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_consistent"("internal", "anyenum", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_consistent"("internal", "anyenum", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_enum_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_enum_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_enum_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_enum_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_consistent"("internal", real, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_consistent"("internal", real, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_consistent"("internal", real, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_consistent"("internal", real, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_distance"("internal", real, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_distance"("internal", real, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_distance"("internal", real, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_distance"("internal", real, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float4_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float4_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float4_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float4_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_consistent"("internal", double precision, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_consistent"("internal", double precision, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_consistent"("internal", double precision, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_consistent"("internal", double precision, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_distance"("internal", double precision, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_distance"("internal", double precision, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_distance"("internal", double precision, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_distance"("internal", double precision, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_float8_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_float8_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_float8_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_float8_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_consistent"("internal", "inet", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_consistent"("internal", "inet", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_consistent"("internal", "inet", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_consistent"("internal", "inet", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_inet_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_inet_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_inet_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_inet_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_consistent"("internal", smallint, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_consistent"("internal", smallint, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_consistent"("internal", smallint, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_consistent"("internal", smallint, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_distance"("internal", smallint, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_distance"("internal", smallint, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_distance"("internal", smallint, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_distance"("internal", smallint, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_same"("public"."gbtreekey4", "public"."gbtreekey4", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_same"("public"."gbtreekey4", "public"."gbtreekey4", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_same"("public"."gbtreekey4", "public"."gbtreekey4", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_same"("public"."gbtreekey4", "public"."gbtreekey4", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int2_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int2_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int2_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int2_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_consistent"("internal", integer, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_consistent"("internal", integer, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_consistent"("internal", integer, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_consistent"("internal", integer, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_distance"("internal", integer, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_distance"("internal", integer, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_distance"("internal", integer, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_distance"("internal", integer, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int4_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int4_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int4_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int4_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_consistent"("internal", bigint, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_consistent"("internal", bigint, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_consistent"("internal", bigint, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_consistent"("internal", bigint, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_distance"("internal", bigint, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_distance"("internal", bigint, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_distance"("internal", bigint, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_distance"("internal", bigint, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_int8_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_int8_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_int8_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_int8_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_consistent"("internal", interval, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_consistent"("internal", interval, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_consistent"("internal", interval, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_consistent"("internal", interval, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_decompress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_decompress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_decompress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_decompress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_distance"("internal", interval, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_distance"("internal", interval, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_distance"("internal", interval, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_distance"("internal", interval, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_intv_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_intv_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_intv_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_intv_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_consistent"("internal", "macaddr8", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_consistent"("internal", "macaddr8", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_consistent"("internal", "macaddr8", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_consistent"("internal", "macaddr8", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad8_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad8_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad8_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad8_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_consistent"("internal", "macaddr", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_consistent"("internal", "macaddr", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_consistent"("internal", "macaddr", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_consistent"("internal", "macaddr", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_macad_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_macad_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_macad_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_macad_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_consistent"("internal", numeric, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_consistent"("internal", numeric, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_consistent"("internal", numeric, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_consistent"("internal", numeric, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_numeric_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_numeric_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_numeric_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_numeric_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_consistent"("internal", "oid", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_consistent"("internal", "oid", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_consistent"("internal", "oid", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_consistent"("internal", "oid", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_distance"("internal", "oid", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_distance"("internal", "oid", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_distance"("internal", "oid", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_distance"("internal", "oid", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_same"("public"."gbtreekey8", "public"."gbtreekey8", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_oid_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_oid_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_oid_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_oid_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_consistent"("internal", "text", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_consistent"("internal", "text", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_consistent"("internal", "text", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_consistent"("internal", "text", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_same"("public"."gbtreekey_var", "public"."gbtreekey_var", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_text_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_text_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_text_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_text_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_consistent"("internal", time without time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_consistent"("internal", time without time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_consistent"("internal", time without time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_consistent"("internal", time without time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_distance"("internal", time without time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_distance"("internal", time without time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_distance"("internal", time without time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_distance"("internal", time without time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_time_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_time_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_time_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_time_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_timetz_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_timetz_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_timetz_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_timetz_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_timetz_consistent"("internal", time with time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_timetz_consistent"("internal", time with time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_timetz_consistent"("internal", time with time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_timetz_consistent"("internal", time with time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_consistent"("internal", timestamp without time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_consistent"("internal", timestamp without time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_consistent"("internal", timestamp without time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_consistent"("internal", timestamp without time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_distance"("internal", timestamp without time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_distance"("internal", timestamp without time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_distance"("internal", timestamp without time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_distance"("internal", timestamp without time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_same"("public"."gbtreekey16", "public"."gbtreekey16", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_ts_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_ts_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_ts_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_ts_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_tstz_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_tstz_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_tstz_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_tstz_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_tstz_consistent"("internal", timestamp with time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_tstz_consistent"("internal", timestamp with time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_tstz_consistent"("internal", timestamp with time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_tstz_consistent"("internal", timestamp with time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_tstz_distance"("internal", timestamp with time zone, smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_tstz_distance"("internal", timestamp with time zone, smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_tstz_distance"("internal", timestamp with time zone, smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_tstz_distance"("internal", timestamp with time zone, smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_consistent"("internal", "uuid", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_consistent"("internal", "uuid", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_consistent"("internal", "uuid", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_consistent"("internal", "uuid", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_same"("public"."gbtreekey32", "public"."gbtreekey32", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_uuid_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_uuid_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_uuid_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_uuid_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_var_decompress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_var_decompress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_var_decompress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_var_decompress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gbt_var_fetch"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gbt_var_fetch"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gbt_var_fetch"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gbt_var_fetch"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_execution_certificate"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_execution_certificate"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_execution_certificate"() TO "service_role";



GRANT ALL ON FUNCTION "public"."geo_distance"("point", "point") TO "postgres";
GRANT ALL ON FUNCTION "public"."geo_distance"("point", "point") TO "anon";
GRANT ALL ON FUNCTION "public"."geo_distance"("point", "point") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geo_distance"("point", "point") TO "service_role";



GRANT ALL ON FUNCTION "public"."geog_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geog_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geog_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geog_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_cmp"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_cmp"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_cmp"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_cmp"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_distance_knn"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_distance_knn"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_distance_knn"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_distance_knn"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_eq"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_eq"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_eq"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_eq"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_ge"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_ge"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_ge"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_ge"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gist_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gist_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gist_consistent"("internal", "public"."geography", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gist_consistent"("internal", "public"."geography", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_consistent"("internal", "public"."geography", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_consistent"("internal", "public"."geography", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gist_decompress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gist_decompress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_decompress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_decompress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gist_distance"("internal", "public"."geography", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gist_distance"("internal", "public"."geography", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_distance"("internal", "public"."geography", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_distance"("internal", "public"."geography", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gist_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gist_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gist_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gist_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gist_same"("public"."box2d", "public"."box2d", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gist_same"("public"."box2d", "public"."box2d", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_same"("public"."box2d", "public"."box2d", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_same"("public"."box2d", "public"."box2d", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gist_union"("bytea", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gist_union"("bytea", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gist_union"("bytea", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gist_union"("bytea", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_gt"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_gt"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_gt"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_gt"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_le"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_le"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_le"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_le"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_lt"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_lt"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_lt"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_lt"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_overlaps"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_overlaps"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_overlaps"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_overlaps"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_spgist_choose_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_spgist_choose_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_choose_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_choose_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_spgist_compress_nd"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_spgist_compress_nd"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_compress_nd"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_compress_nd"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_spgist_config_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_spgist_config_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_config_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_config_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_spgist_inner_consistent_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_spgist_inner_consistent_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_inner_consistent_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_inner_consistent_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_spgist_leaf_consistent_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_spgist_leaf_consistent_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_leaf_consistent_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_leaf_consistent_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geography_spgist_picksplit_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geography_spgist_picksplit_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geography_spgist_picksplit_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geography_spgist_picksplit_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geom2d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geom2d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geom2d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geom2d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geom3d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geom3d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geom3d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geom3d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geom4d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geom4d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geom4d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geom4d_brin_inclusion_add_value"("internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_above"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_above"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_above"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_above"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_below"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_below"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_below"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_below"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_cmp"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_cmp"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_cmp"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_cmp"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_contained_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_contained_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_contained_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_contained_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_contains_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_contains_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_contains_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_contains_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_contains_nd"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_contains_nd"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_contains_nd"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_contains_nd"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_distance_box"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_distance_box"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_distance_box"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_distance_box"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_distance_centroid"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_distance_centroid"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_distance_centroid"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_distance_centroid"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_distance_centroid_nd"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_distance_centroid_nd"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_distance_centroid_nd"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_distance_centroid_nd"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_distance_cpa"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_distance_cpa"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_distance_cpa"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_distance_cpa"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_eq"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_eq"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_eq"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_eq"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_ge"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_ge"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_ge"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_ge"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_compress_2d"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_compress_2d"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_compress_2d"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_compress_2d"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_compress_nd"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_compress_nd"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_compress_nd"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_compress_nd"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_2d"("internal", "public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_2d"("internal", "public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_2d"("internal", "public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_2d"("internal", "public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_nd"("internal", "public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_nd"("internal", "public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_nd"("internal", "public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_consistent_nd"("internal", "public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_2d"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_2d"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_2d"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_2d"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_nd"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_nd"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_nd"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_decompress_nd"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_distance_2d"("internal", "public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_distance_2d"("internal", "public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_distance_2d"("internal", "public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_distance_2d"("internal", "public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_distance_nd"("internal", "public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_distance_nd"("internal", "public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_distance_nd"("internal", "public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_distance_nd"("internal", "public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_2d"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_2d"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_2d"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_2d"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_nd"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_nd"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_nd"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_penalty_nd"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_2d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_2d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_2d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_2d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_picksplit_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_same_2d"("geom1" "public"."geometry", "geom2" "public"."geometry", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_same_2d"("geom1" "public"."geometry", "geom2" "public"."geometry", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_same_2d"("geom1" "public"."geometry", "geom2" "public"."geometry", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_same_2d"("geom1" "public"."geometry", "geom2" "public"."geometry", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_same_nd"("public"."geometry", "public"."geometry", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_same_nd"("public"."geometry", "public"."geometry", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_same_nd"("public"."geometry", "public"."geometry", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_same_nd"("public"."geometry", "public"."geometry", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_sortsupport_2d"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_sortsupport_2d"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_sortsupport_2d"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_sortsupport_2d"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_union_2d"("bytea", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_union_2d"("bytea", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_union_2d"("bytea", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_union_2d"("bytea", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gist_union_nd"("bytea", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gist_union_nd"("bytea", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gist_union_nd"("bytea", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gist_union_nd"("bytea", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_gt"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_gt"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_gt"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_gt"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_hash"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_hash"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_hash"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_hash"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_le"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_le"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_le"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_le"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_left"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_left"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_left"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_left"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_lt"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_lt"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_lt"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_lt"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_overabove"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_overabove"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overabove"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overabove"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_overbelow"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_overbelow"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overbelow"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overbelow"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_overlaps_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_overlaps_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overlaps_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overlaps_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_overlaps_nd"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_overlaps_nd"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overlaps_nd"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overlaps_nd"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_overleft"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_overleft"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overleft"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overleft"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_overright"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_overright"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_overright"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_overright"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_right"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_right"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_right"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_right"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_same"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_same"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_same"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_same"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_same_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_same_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_same_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_same_3d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_same_nd"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_same_nd"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_same_nd"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_same_nd"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_sortsupport"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_sortsupport"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_sortsupport"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_sortsupport"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_2d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_2d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_2d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_2d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_3d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_3d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_3d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_3d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_choose_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_2d"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_2d"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_2d"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_2d"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_3d"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_3d"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_3d"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_3d"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_nd"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_nd"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_nd"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_compress_nd"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_config_2d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_2d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_2d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_2d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_config_3d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_3d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_3d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_3d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_config_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_config_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_2d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_2d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_2d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_2d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_3d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_3d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_3d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_3d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_inner_consistent_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_2d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_2d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_2d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_2d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_3d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_3d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_3d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_3d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_leaf_consistent_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_2d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_2d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_2d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_2d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_3d"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_3d"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_3d"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_3d"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_nd"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_nd"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_nd"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_spgist_picksplit_nd"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometry_within_nd"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometry_within_nd"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometry_within_nd"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometry_within_nd"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometrytype"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometrytype"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."geometrytype"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometrytype"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."geometrytype"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."geometrytype"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."geometrytype"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geometrytype"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."geomfromewkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."geomfromewkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."geomfromewkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geomfromewkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."geomfromewkt"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."geomfromewkt"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."geomfromewkt"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geomfromewkt"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_admin_business_metrics"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_admin_business_metrics"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_admin_business_metrics"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_auth_user_fleet_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_auth_user_fleet_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_auth_user_fleet_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_auth_user_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_auth_user_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_auth_user_role"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_fleet_friction_metrics"("p_fleet_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_fleet_friction_metrics"("p_fleet_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_fleet_friction_metrics"("p_fleet_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."access_logs" TO "anon";
GRANT ALL ON TABLE "public"."access_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."access_logs" TO "service_role";



GRANT ALL ON FUNCTION "public"."get_offer_chronology"("offer_uuid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_offer_chronology"("offer_uuid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_offer_chronology"("offer_uuid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_proj4_from_srid"(integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."get_proj4_from_srid"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_proj4_from_srid"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_proj4_from_srid"(integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."gettransactionid"() TO "postgres";
GRANT ALL ON FUNCTION "public"."gettransactionid"() TO "anon";
GRANT ALL ON FUNCTION "public"."gettransactionid"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."gettransactionid"() TO "service_role";



GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_2d"("internal", "oid", "internal", smallint) TO "postgres";
GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_2d"("internal", "oid", "internal", smallint) TO "anon";
GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_2d"("internal", "oid", "internal", smallint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_2d"("internal", "oid", "internal", smallint) TO "service_role";



GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_nd"("internal", "oid", "internal", smallint) TO "postgres";
GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_nd"("internal", "oid", "internal", smallint) TO "anon";
GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_nd"("internal", "oid", "internal", smallint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gserialized_gist_joinsel_nd"("internal", "oid", "internal", smallint) TO "service_role";



GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_2d"("internal", "oid", "internal", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_2d"("internal", "oid", "internal", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_2d"("internal", "oid", "internal", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_2d"("internal", "oid", "internal", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_nd"("internal", "oid", "internal", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_nd"("internal", "oid", "internal", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_nd"("internal", "oid", "internal", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gserialized_gist_sel_nd"("internal", "oid", "internal", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("full_name") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("updated_at") ON TABLE "public"."profiles" TO "authenticated";



GRANT ALL ON FUNCTION "public"."insurance_compliant"("public"."profiles") TO "anon";
GRANT ALL ON FUNCTION "public"."insurance_compliant"("public"."profiles") TO "authenticated";
GRANT ALL ON FUNCTION "public"."insurance_compliant"("public"."profiles") TO "service_role";



GRANT ALL ON FUNCTION "public"."int2_dist"(smallint, smallint) TO "postgres";
GRANT ALL ON FUNCTION "public"."int2_dist"(smallint, smallint) TO "anon";
GRANT ALL ON FUNCTION "public"."int2_dist"(smallint, smallint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."int2_dist"(smallint, smallint) TO "service_role";



GRANT ALL ON FUNCTION "public"."int4_dist"(integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."int4_dist"(integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."int4_dist"(integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."int4_dist"(integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."int8_dist"(bigint, bigint) TO "postgres";
GRANT ALL ON FUNCTION "public"."int8_dist"(bigint, bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."int8_dist"(bigint, bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."int8_dist"(bigint, bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."interval_dist"(interval, interval) TO "postgres";
GRANT ALL ON FUNCTION "public"."interval_dist"(interval, interval) TO "anon";
GRANT ALL ON FUNCTION "public"."interval_dist"(interval, interval) TO "authenticated";
GRANT ALL ON FUNCTION "public"."interval_dist"(interval, interval) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."box2df", "public"."box2df") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."box2df", "public"."box2df") TO "anon";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."box2df", "public"."box2df") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."box2df", "public"."box2df") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."box2df", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."box2df", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."box2df", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."box2df", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."geometry", "public"."box2df") TO "postgres";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."geometry", "public"."box2df") TO "anon";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."geometry", "public"."box2df") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_contained_2d"("public"."geometry", "public"."box2df") TO "service_role";



GRANT ALL ON FUNCTION "public"."join_jit_queue"("p_asset_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."join_jit_queue"("p_asset_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."join_jit_queue"("p_asset_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."latitude"("public"."earth") TO "postgres";
GRANT ALL ON FUNCTION "public"."latitude"("public"."earth") TO "anon";
GRANT ALL ON FUNCTION "public"."latitude"("public"."earth") TO "authenticated";
GRANT ALL ON FUNCTION "public"."latitude"("public"."earth") TO "service_role";



GRANT ALL ON FUNCTION "public"."leave_jit_queue"("p_asset_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."leave_jit_queue"("p_asset_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."leave_jit_queue"("p_asset_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."ll_to_earth"(double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."ll_to_earth"(double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."ll_to_earth"(double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."ll_to_earth"(double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."lock_asset_preventively"("p_asset_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."lock_asset_preventively"("p_asset_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lock_asset_preventively"("p_asset_id" "uuid", "p_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", timestamp without time zone) TO "postgres";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", timestamp without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", timestamp without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", timestamp without time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", "text", timestamp without time zone) TO "postgres";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", "text", timestamp without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", "text", timestamp without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."lockrow"("text", "text", "text", "text", timestamp without time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."log_infrastructure_mutation"() TO "anon";
GRANT ALL ON FUNCTION "public"."log_infrastructure_mutation"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_infrastructure_mutation"() TO "service_role";



GRANT ALL ON FUNCTION "public"."longitude"("public"."earth") TO "postgres";
GRANT ALL ON FUNCTION "public"."longitude"("public"."earth") TO "anon";
GRANT ALL ON FUNCTION "public"."longitude"("public"."earth") TO "authenticated";
GRANT ALL ON FUNCTION "public"."longitude"("public"."earth") TO "service_role";



GRANT ALL ON FUNCTION "public"."longtransactionsenabled"() TO "postgres";
GRANT ALL ON FUNCTION "public"."longtransactionsenabled"() TO "anon";
GRANT ALL ON FUNCTION "public"."longtransactionsenabled"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."longtransactionsenabled"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_prestart_commenced"("p_assignment_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_prestart_commenced"("p_assignment_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_prestart_commenced"("p_assignment_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."matches_contractor_profile"("driver_uuid" "uuid", "offer_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."matches_contractor_profile"("driver_uuid" "uuid", "offer_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."matches_contractor_profile"("driver_uuid" "uuid", "offer_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."matchmaker_dispatch_on_excavator_ready"() TO "anon";
GRANT ALL ON FUNCTION "public"."matchmaker_dispatch_on_excavator_ready"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."matchmaker_dispatch_on_excavator_ready"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_edge_function_on_certificate"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_edge_function_on_certificate"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_edge_function_on_certificate"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_edge_function_on_critical_audit"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_edge_function_on_critical_audit"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_edge_function_on_critical_audit"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_edge_function_on_lock"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_edge_function_on_lock"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_edge_function_on_lock"() TO "service_role";



GRANT ALL ON FUNCTION "public"."oid_dist"("oid", "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."oid_dist"("oid", "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."oid_dist"("oid", "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."oid_dist"("oid", "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."box2df", "public"."box2df") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."box2df", "public"."box2df") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."box2df", "public"."box2df") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."box2df", "public"."box2df") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."box2df", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."box2df", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."box2df", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."box2df", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."geometry", "public"."box2df") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."geometry", "public"."box2df") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."geometry", "public"."box2df") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_2d"("public"."geometry", "public"."box2df") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."geography", "public"."gidx") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."geography", "public"."gidx") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."geography", "public"."gidx") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."geography", "public"."gidx") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."gidx", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."gidx", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."gidx", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."gidx", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."gidx", "public"."gidx") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."gidx", "public"."gidx") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."gidx", "public"."gidx") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_geog"("public"."gidx", "public"."gidx") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."geometry", "public"."gidx") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."geometry", "public"."gidx") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."geometry", "public"."gidx") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."geometry", "public"."gidx") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."gidx", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."gidx", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."gidx", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."gidx", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."gidx", "public"."gidx") TO "postgres";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."gidx", "public"."gidx") TO "anon";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."gidx", "public"."gidx") TO "authenticated";
GRANT ALL ON FUNCTION "public"."overlaps_nd"("public"."gidx", "public"."gidx") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement", boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement", boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement", boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement", boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement", boolean, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement", boolean, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement", boolean, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asflatgeobuf_transfn"("internal", "anyelement", boolean, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"("internal", "anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"("internal", "anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"("internal", "anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"("internal", "anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"("internal", "anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"("internal", "anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"("internal", "anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asgeobuf_transfn"("internal", "anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_combinefn"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_combinefn"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_combinefn"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_combinefn"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_deserialfn"("bytea", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_deserialfn"("bytea", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_deserialfn"("bytea", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_deserialfn"("bytea", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_serialfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_serialfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_serialfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_serialfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer, "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer, "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer, "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_asmvt_transfn"("internal", "anyelement", "text", integer, "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry", double precision, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry", double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry", double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_accum_transfn"("internal", "public"."geometry", double precision, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterintersecting_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterintersecting_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterintersecting_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterintersecting_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterwithin_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterwithin_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterwithin_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_clusterwithin_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_collect_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_collect_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_collect_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_collect_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_makeline_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_makeline_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_makeline_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_makeline_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_polygonize_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_polygonize_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_polygonize_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_polygonize_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_combinefn"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_combinefn"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_combinefn"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_combinefn"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_deserialfn"("bytea", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_deserialfn"("bytea", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_deserialfn"("bytea", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_deserialfn"("bytea", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_finalfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_finalfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_finalfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_finalfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_serialfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_serialfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_serialfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_serialfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_transfn"("internal", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_transfn"("internal", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_transfn"("internal", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_transfn"("internal", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_transfn"("internal", "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_transfn"("internal", "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_transfn"("internal", "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."pgis_geometry_union_parallel_transfn"("internal", "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."populate_geometry_columns"("use_typmod" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."populate_geometry_columns"("use_typmod" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."populate_geometry_columns"("use_typmod" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."populate_geometry_columns"("use_typmod" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."populate_geometry_columns"("tbl_oid" "oid", "use_typmod" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."populate_geometry_columns"("tbl_oid" "oid", "use_typmod" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."populate_geometry_columns"("tbl_oid" "oid", "use_typmod" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."populate_geometry_columns"("tbl_oid" "oid", "use_typmod" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_addbbox"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_addbbox"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_addbbox"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_addbbox"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_cache_bbox"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_cache_bbox"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_cache_bbox"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_cache_bbox"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_constraint_dims"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_constraint_dims"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_constraint_dims"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_constraint_dims"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_constraint_srid"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_constraint_srid"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_constraint_srid"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_constraint_srid"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_constraint_type"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_constraint_type"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_constraint_type"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_constraint_type"("geomschema" "text", "geomtable" "text", "geomcolumn" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_dropbbox"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_dropbbox"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_dropbbox"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_dropbbox"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_extensions_upgrade"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_extensions_upgrade"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_extensions_upgrade"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_extensions_upgrade"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_full_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_full_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_full_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_full_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_geos_noop"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_geos_noop"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_geos_noop"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_geos_noop"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_geos_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_geos_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_geos_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_geos_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_getbbox"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_getbbox"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_getbbox"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_getbbox"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_hasbbox"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_hasbbox"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_hasbbox"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_hasbbox"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_index_supportfn"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_index_supportfn"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_index_supportfn"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_index_supportfn"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_lib_build_date"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_lib_build_date"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_lib_build_date"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_lib_build_date"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_lib_revision"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_lib_revision"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_lib_revision"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_lib_revision"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_lib_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_lib_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_lib_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_lib_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_libjson_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_libjson_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_libjson_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_libjson_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_liblwgeom_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_liblwgeom_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_liblwgeom_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_liblwgeom_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_libprotobuf_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_libprotobuf_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_libprotobuf_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_libprotobuf_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_libxml_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_libxml_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_libxml_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_libxml_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_noop"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_noop"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_noop"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_noop"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_proj_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_proj_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_proj_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_proj_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_scripts_build_date"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_scripts_build_date"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_scripts_build_date"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_scripts_build_date"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_scripts_installed"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_scripts_installed"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_scripts_installed"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_scripts_installed"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_scripts_released"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_scripts_released"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_scripts_released"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_scripts_released"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_svn_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_svn_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_svn_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_svn_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_transform_geometry"("geom" "public"."geometry", "text", "text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_transform_geometry"("geom" "public"."geometry", "text", "text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_transform_geometry"("geom" "public"."geometry", "text", "text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_transform_geometry"("geom" "public"."geometry", "text", "text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_type_name"("geomname" character varying, "coord_dimension" integer, "use_new_name" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_type_name"("geomname" character varying, "coord_dimension" integer, "use_new_name" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_type_name"("geomname" character varying, "coord_dimension" integer, "use_new_name" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_type_name"("geomname" character varying, "coord_dimension" integer, "use_new_name" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_typmod_dims"(integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_typmod_dims"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_typmod_dims"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_typmod_dims"(integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_typmod_srid"(integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_typmod_srid"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_typmod_srid"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_typmod_srid"(integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_typmod_type"(integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_typmod_type"(integer) TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_typmod_type"(integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_typmod_type"(integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."postgis_wagyu_version"() TO "postgres";
GRANT ALL ON FUNCTION "public"."postgis_wagyu_version"() TO "anon";
GRANT ALL ON FUNCTION "public"."postgis_wagyu_version"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."postgis_wagyu_version"() TO "service_role";



GRANT ALL ON FUNCTION "public"."process_handover_signature"() TO "anon";
GRANT ALL ON FUNCTION "public"."process_handover_signature"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."process_handover_signature"() TO "service_role";



GRANT ALL ON FUNCTION "public"."process_quarantined_expense"("p_expense_id" "uuid", "p_status" character varying, "p_corrected_amount" numeric, "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."process_quarantined_expense"("p_expense_id" "uuid", "p_status" character varying, "p_corrected_amount" numeric, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."process_quarantined_expense"("p_expense_id" "uuid", "p_status" character varying, "p_corrected_amount" numeric, "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."process_telemetry_safety_override"() TO "anon";
GRANT ALL ON FUNCTION "public"."process_telemetry_safety_override"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."process_telemetry_safety_override"() TO "service_role";



GRANT ALL ON FUNCTION "public"."process_webhook_responses"() TO "anon";
GRANT ALL ON FUNCTION "public"."process_webhook_responses"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."process_webhook_responses"() TO "service_role";



GRANT ALL ON FUNCTION "public"."project_asset_telemetry_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."project_asset_telemetry_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."project_asset_telemetry_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."protect_contract_lifecycle"() TO "anon";
GRANT ALL ON FUNCTION "public"."protect_contract_lifecycle"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."protect_contract_lifecycle"() TO "service_role";



GRANT ALL ON FUNCTION "public"."protect_forensic_hash"() TO "anon";
GRANT ALL ON FUNCTION "public"."protect_forensic_hash"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."protect_forensic_hash"() TO "service_role";



GRANT ALL ON FUNCTION "public"."push_to_n8n_webhook"() TO "anon";
GRANT ALL ON FUNCTION "public"."push_to_n8n_webhook"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."push_to_n8n_webhook"() TO "service_role";



GRANT ALL ON FUNCTION "public"."queue_erp_outbox"() TO "anon";
GRANT ALL ON FUNCTION "public"."queue_erp_outbox"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."queue_erp_outbox"() TO "service_role";



GRANT ALL ON FUNCTION "public"."reconcile_load_cycle"("p_cycle_id" "uuid", "p_gross_weight" numeric, "p_tare_weight" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."reconcile_load_cycle"("p_cycle_id" "uuid", "p_gross_weight" numeric, "p_tare_weight" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."reconcile_load_cycle"("p_cycle_id" "uuid", "p_gross_weight" numeric, "p_tare_weight" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."refresh_managerial_kpis"() TO "anon";
GRANT ALL ON FUNCTION "public"."refresh_managerial_kpis"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."refresh_managerial_kpis"() TO "service_role";



GRANT ALL ON FUNCTION "public"."release_asset_from_maintenance"("p_asset_id" "uuid", "p_release_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."release_asset_from_maintenance"("p_asset_id" "uuid", "p_release_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."release_asset_from_maintenance"("p_asset_id" "uuid", "p_release_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."report_incident"("p_offer_id" "uuid", "p_description" "text", "p_lat" numeric, "p_lng" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."report_incident"("p_offer_id" "uuid", "p_description" "text", "p_lat" numeric, "p_lng" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."report_incident"("p_offer_id" "uuid", "p_description" "text", "p_lat" numeric, "p_lng" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."resolve_plant_defect"("p_defect_id" "uuid", "p_category" "public"."defect_category", "p_resolution_notes" "text", "p_mechanic_pin" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_plant_defect"("p_defect_id" "uuid", "p_category" "public"."defect_category", "p_resolution_notes" "text", "p_mechanic_pin" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_plant_defect"("p_defect_id" "uuid", "p_category" "public"."defect_category", "p_resolution_notes" "text", "p_mechanic_pin" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."resurrect_dead_letter"("p_outbox_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."resurrect_dead_letter"("p_outbox_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resurrect_dead_letter"("p_outbox_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."revoke_pending_shift"("p_assignment_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."revoke_pending_shift"("p_assignment_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."revoke_pending_shift"("p_assignment_id" "uuid", "p_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."seed_test_trip"() TO "anon";
GRANT ALL ON FUNCTION "public"."seed_test_trip"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."seed_test_trip"() TO "service_role";



GRANT ALL ON FUNCTION "public"."simulate_docket_ocr"() TO "anon";
GRANT ALL ON FUNCTION "public"."simulate_docket_ocr"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."simulate_docket_ocr"() TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dclosestpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dclosestpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dclosestpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dclosestpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3ddfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3ddfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3ddfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3ddfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3ddistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3ddistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3ddistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3ddistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3ddwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3ddwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3ddwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3ddwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dintersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dintersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dintersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dintersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dlength"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dlength"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dlength"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dlength"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dlineinterpolatepoint"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dlineinterpolatepoint"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dlineinterpolatepoint"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dlineinterpolatepoint"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dlongestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dlongestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dlongestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dlongestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dmakebox"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dmakebox"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dmakebox"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dmakebox"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dmaxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dmaxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dmaxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dmaxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dperimeter"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dperimeter"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dperimeter"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dperimeter"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_3dshortestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dshortestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dshortestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dshortestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_addmeasure"("public"."geometry", double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_addmeasure"("public"."geometry", double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_addmeasure"("public"."geometry", double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_addmeasure"("public"."geometry", double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_addpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_addpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_addpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_addpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_addpoint"("geom1" "public"."geometry", "geom2" "public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_addpoint"("geom1" "public"."geometry", "geom2" "public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_addpoint"("geom1" "public"."geometry", "geom2" "public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_addpoint"("geom1" "public"."geometry", "geom2" "public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_affine"("public"."geometry", double precision, double precision, double precision, double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_affine"("public"."geometry", double precision, double precision, double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_affine"("public"."geometry", double precision, double precision, double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_affine"("public"."geometry", double precision, double precision, double precision, double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_affine"("public"."geometry", double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_affine"("public"."geometry", double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_affine"("public"."geometry", double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_affine"("public"."geometry", double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_angle"("line1" "public"."geometry", "line2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_angle"("line1" "public"."geometry", "line2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_angle"("line1" "public"."geometry", "line2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_angle"("line1" "public"."geometry", "line2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_angle"("pt1" "public"."geometry", "pt2" "public"."geometry", "pt3" "public"."geometry", "pt4" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_angle"("pt1" "public"."geometry", "pt2" "public"."geometry", "pt3" "public"."geometry", "pt4" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_angle"("pt1" "public"."geometry", "pt2" "public"."geometry", "pt3" "public"."geometry", "pt4" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_angle"("pt1" "public"."geometry", "pt2" "public"."geometry", "pt3" "public"."geometry", "pt4" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_area"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_area"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_area"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_area"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_area"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_area"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_area"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_area"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_area"("geog" "public"."geography", "use_spheroid" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_area"("geog" "public"."geography", "use_spheroid" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_area"("geog" "public"."geography", "use_spheroid" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_area"("geog" "public"."geography", "use_spheroid" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_area2d"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_area2d"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_area2d"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_area2d"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geography", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geography", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geography", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geography", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geometry", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geometry", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geometry", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asbinary"("public"."geometry", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asencodedpolyline"("geom" "public"."geometry", "nprecision" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asencodedpolyline"("geom" "public"."geometry", "nprecision" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asencodedpolyline"("geom" "public"."geometry", "nprecision" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asencodedpolyline"("geom" "public"."geometry", "nprecision" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asewkb"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asewkb"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkb"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkb"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asewkb"("public"."geometry", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asewkb"("public"."geometry", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkb"("public"."geometry", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkb"("public"."geometry", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asewkt"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asewkt"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkt"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkt"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geography", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geography", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geography", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geography", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asewkt"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgeojson"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgeojson"("geog" "public"."geography", "maxdecimaldigits" integer, "options" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("geog" "public"."geography", "maxdecimaldigits" integer, "options" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("geog" "public"."geography", "maxdecimaldigits" integer, "options" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("geog" "public"."geography", "maxdecimaldigits" integer, "options" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgeojson"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgeojson"("r" "record", "geom_column" "text", "maxdecimaldigits" integer, "pretty_bool" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("r" "record", "geom_column" "text", "maxdecimaldigits" integer, "pretty_bool" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("r" "record", "geom_column" "text", "maxdecimaldigits" integer, "pretty_bool" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeojson"("r" "record", "geom_column" "text", "maxdecimaldigits" integer, "pretty_bool" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgml"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgml"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgml"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgml"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgml"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgml"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgml"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgml"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgml"("geog" "public"."geography", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgml"("geog" "public"."geography", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgml"("geog" "public"."geography", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgml"("geog" "public"."geography", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgml"("version" integer, "geog" "public"."geography", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgml"("version" integer, "geog" "public"."geography", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgml"("version" integer, "geog" "public"."geography", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgml"("version" integer, "geog" "public"."geography", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgml"("version" integer, "geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgml"("version" integer, "geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgml"("version" integer, "geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgml"("version" integer, "geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer, "nprefix" "text", "id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_ashexewkb"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_ashexewkb"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_ashexewkb"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ashexewkb"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_ashexewkb"("public"."geometry", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_ashexewkb"("public"."geometry", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_ashexewkb"("public"."geometry", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ashexewkb"("public"."geometry", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_askml"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_askml"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_askml"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_askml"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_askml"("geog" "public"."geography", "maxdecimaldigits" integer, "nprefix" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_askml"("geog" "public"."geography", "maxdecimaldigits" integer, "nprefix" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_askml"("geog" "public"."geography", "maxdecimaldigits" integer, "nprefix" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_askml"("geog" "public"."geography", "maxdecimaldigits" integer, "nprefix" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_askml"("geom" "public"."geometry", "maxdecimaldigits" integer, "nprefix" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_askml"("geom" "public"."geometry", "maxdecimaldigits" integer, "nprefix" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_askml"("geom" "public"."geometry", "maxdecimaldigits" integer, "nprefix" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_askml"("geom" "public"."geometry", "maxdecimaldigits" integer, "nprefix" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_aslatlontext"("geom" "public"."geometry", "tmpl" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_aslatlontext"("geom" "public"."geometry", "tmpl" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_aslatlontext"("geom" "public"."geometry", "tmpl" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_aslatlontext"("geom" "public"."geometry", "tmpl" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asmarc21"("geom" "public"."geometry", "format" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asmarc21"("geom" "public"."geometry", "format" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmarc21"("geom" "public"."geometry", "format" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmarc21"("geom" "public"."geometry", "format" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asmvtgeom"("geom" "public"."geometry", "bounds" "public"."box2d", "extent" integer, "buffer" integer, "clip_geom" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asmvtgeom"("geom" "public"."geometry", "bounds" "public"."box2d", "extent" integer, "buffer" integer, "clip_geom" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvtgeom"("geom" "public"."geometry", "bounds" "public"."box2d", "extent" integer, "buffer" integer, "clip_geom" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvtgeom"("geom" "public"."geometry", "bounds" "public"."box2d", "extent" integer, "buffer" integer, "clip_geom" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_assvg"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_assvg"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_assvg"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_assvg"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_assvg"("geog" "public"."geography", "rel" integer, "maxdecimaldigits" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_assvg"("geog" "public"."geography", "rel" integer, "maxdecimaldigits" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_assvg"("geog" "public"."geography", "rel" integer, "maxdecimaldigits" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_assvg"("geog" "public"."geography", "rel" integer, "maxdecimaldigits" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_assvg"("geom" "public"."geometry", "rel" integer, "maxdecimaldigits" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_assvg"("geom" "public"."geometry", "rel" integer, "maxdecimaldigits" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_assvg"("geom" "public"."geometry", "rel" integer, "maxdecimaldigits" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_assvg"("geom" "public"."geometry", "rel" integer, "maxdecimaldigits" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_astext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_astext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_astext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_astext"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_astext"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_astext"("public"."geography", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geography", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geography", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geography", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_astext"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astext"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_astwkb"("geom" "public"."geometry", "prec" integer, "prec_z" integer, "prec_m" integer, "with_sizes" boolean, "with_boxes" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_astwkb"("geom" "public"."geometry", "prec" integer, "prec_z" integer, "prec_m" integer, "with_sizes" boolean, "with_boxes" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_astwkb"("geom" "public"."geometry", "prec" integer, "prec_z" integer, "prec_m" integer, "with_sizes" boolean, "with_boxes" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astwkb"("geom" "public"."geometry", "prec" integer, "prec_z" integer, "prec_m" integer, "with_sizes" boolean, "with_boxes" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_astwkb"("geom" "public"."geometry"[], "ids" bigint[], "prec" integer, "prec_z" integer, "prec_m" integer, "with_sizes" boolean, "with_boxes" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_astwkb"("geom" "public"."geometry"[], "ids" bigint[], "prec" integer, "prec_z" integer, "prec_m" integer, "with_sizes" boolean, "with_boxes" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_astwkb"("geom" "public"."geometry"[], "ids" bigint[], "prec" integer, "prec_z" integer, "prec_m" integer, "with_sizes" boolean, "with_boxes" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_astwkb"("geom" "public"."geometry"[], "ids" bigint[], "prec" integer, "prec_z" integer, "prec_m" integer, "with_sizes" boolean, "with_boxes" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asx3d"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asx3d"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asx3d"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asx3d"("geom" "public"."geometry", "maxdecimaldigits" integer, "options" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_azimuth"("geog1" "public"."geography", "geog2" "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_azimuth"("geog1" "public"."geography", "geog2" "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_azimuth"("geog1" "public"."geography", "geog2" "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_azimuth"("geog1" "public"."geography", "geog2" "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_azimuth"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_azimuth"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_azimuth"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_azimuth"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_bdmpolyfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_bdmpolyfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_bdmpolyfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_bdmpolyfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_bdpolyfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_bdpolyfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_bdpolyfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_bdpolyfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_boundary"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_boundary"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_boundary"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_boundary"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_boundingdiagonal"("geom" "public"."geometry", "fits" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_boundingdiagonal"("geom" "public"."geometry", "fits" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_boundingdiagonal"("geom" "public"."geometry", "fits" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_boundingdiagonal"("geom" "public"."geometry", "fits" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_box2dfromgeohash"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_box2dfromgeohash"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_box2dfromgeohash"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_box2dfromgeohash"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"("text", double precision, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"("public"."geography", double precision, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buffer"("geom" "public"."geometry", "radius" double precision, "quadsegs" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buffer"("geom" "public"."geometry", "radius" double precision, "quadsegs" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"("geom" "public"."geometry", "radius" double precision, "quadsegs" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"("geom" "public"."geometry", "radius" double precision, "quadsegs" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buffer"("geom" "public"."geometry", "radius" double precision, "options" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buffer"("geom" "public"."geometry", "radius" double precision, "options" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_buffer"("geom" "public"."geometry", "radius" double precision, "options" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buffer"("geom" "public"."geometry", "radius" double precision, "options" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_buildarea"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_buildarea"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_buildarea"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_buildarea"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_centroid"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_centroid"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_centroid"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_centroid"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_centroid"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_centroid"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_centroid"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_centroid"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_centroid"("public"."geography", "use_spheroid" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_centroid"("public"."geography", "use_spheroid" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_centroid"("public"."geography", "use_spheroid" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_centroid"("public"."geography", "use_spheroid" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_chaikinsmoothing"("public"."geometry", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_chaikinsmoothing"("public"."geometry", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_chaikinsmoothing"("public"."geometry", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_chaikinsmoothing"("public"."geometry", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_cleangeometry"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_cleangeometry"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_cleangeometry"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_cleangeometry"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_clipbybox2d"("geom" "public"."geometry", "box" "public"."box2d") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_clipbybox2d"("geom" "public"."geometry", "box" "public"."box2d") TO "anon";
GRANT ALL ON FUNCTION "public"."st_clipbybox2d"("geom" "public"."geometry", "box" "public"."box2d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clipbybox2d"("geom" "public"."geometry", "box" "public"."box2d") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_closestpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_closestpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_closestpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_closestpoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_closestpointofapproach"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_closestpointofapproach"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_closestpointofapproach"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_closestpointofapproach"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_clusterdbscan"("public"."geometry", "eps" double precision, "minpoints" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_clusterdbscan"("public"."geometry", "eps" double precision, "minpoints" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterdbscan"("public"."geometry", "eps" double precision, "minpoints" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterdbscan"("public"."geometry", "eps" double precision, "minpoints" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_clusterintersecting"("public"."geometry"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_clusterintersecting"("public"."geometry"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterintersecting"("public"."geometry"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterintersecting"("public"."geometry"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_clusterkmeans"("geom" "public"."geometry", "k" integer, "max_radius" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_clusterkmeans"("geom" "public"."geometry", "k" integer, "max_radius" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterkmeans"("geom" "public"."geometry", "k" integer, "max_radius" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterkmeans"("geom" "public"."geometry", "k" integer, "max_radius" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_clusterwithin"("public"."geometry"[], double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_clusterwithin"("public"."geometry"[], double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterwithin"("public"."geometry"[], double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterwithin"("public"."geometry"[], double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_collect"("public"."geometry"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_collect"("public"."geometry"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_collect"("public"."geometry"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collect"("public"."geometry"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_collect"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_collect"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_collect"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collect"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_collectionextract"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_collectionextract"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_collectionextract"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collectionextract"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_collectionextract"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_collectionextract"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_collectionextract"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collectionextract"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_collectionhomogenize"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_collectionhomogenize"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_collectionhomogenize"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collectionhomogenize"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box2d", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box2d", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box2d", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box2d", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box3d", "public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box3d", "public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box3d", "public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box3d", "public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box3d", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box3d", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box3d", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_combinebbox"("public"."box3d", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_concavehull"("param_geom" "public"."geometry", "param_pctconvex" double precision, "param_allow_holes" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_concavehull"("param_geom" "public"."geometry", "param_pctconvex" double precision, "param_allow_holes" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_concavehull"("param_geom" "public"."geometry", "param_pctconvex" double precision, "param_allow_holes" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_concavehull"("param_geom" "public"."geometry", "param_pctconvex" double precision, "param_allow_holes" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_contains"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_containsproperly"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_containsproperly"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_containsproperly"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_containsproperly"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_convexhull"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_convexhull"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_convexhull"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_convexhull"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_coorddim"("geometry" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_coorddim"("geometry" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_coorddim"("geometry" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_coorddim"("geometry" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_coveredby"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_coveredby"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_coveredby"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_coveredby"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_coveredby"("geog1" "public"."geography", "geog2" "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_coveredby"("geog1" "public"."geography", "geog2" "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_coveredby"("geog1" "public"."geography", "geog2" "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_coveredby"("geog1" "public"."geography", "geog2" "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_coveredby"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_coveredby"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_coveredby"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_coveredby"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_covers"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_covers"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_covers"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_covers"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_covers"("geog1" "public"."geography", "geog2" "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_covers"("geog1" "public"."geography", "geog2" "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_covers"("geog1" "public"."geography", "geog2" "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_covers"("geog1" "public"."geography", "geog2" "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_covers"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_covers"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_covers"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_covers"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_cpawithin"("public"."geometry", "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_cpawithin"("public"."geometry", "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_cpawithin"("public"."geometry", "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_cpawithin"("public"."geometry", "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_crosses"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_crosses"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_crosses"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_crosses"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_curvetoline"("geom" "public"."geometry", "tol" double precision, "toltype" integer, "flags" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_curvetoline"("geom" "public"."geometry", "tol" double precision, "toltype" integer, "flags" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_curvetoline"("geom" "public"."geometry", "tol" double precision, "toltype" integer, "flags" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_curvetoline"("geom" "public"."geometry", "tol" double precision, "toltype" integer, "flags" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_delaunaytriangles"("g1" "public"."geometry", "tolerance" double precision, "flags" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_delaunaytriangles"("g1" "public"."geometry", "tolerance" double precision, "flags" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_delaunaytriangles"("g1" "public"."geometry", "tolerance" double precision, "flags" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_delaunaytriangles"("g1" "public"."geometry", "tolerance" double precision, "flags" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_dfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dfullywithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_difference"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_difference"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_difference"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_difference"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dimension"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dimension"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_dimension"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dimension"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_disjoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_disjoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_disjoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_disjoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_distance"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_distance"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_distance"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distance"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_distance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_distance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_distance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_distance"("geog1" "public"."geography", "geog2" "public"."geography", "use_spheroid" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_distance"("geog1" "public"."geography", "geog2" "public"."geography", "use_spheroid" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_distance"("geog1" "public"."geography", "geog2" "public"."geography", "use_spheroid" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distance"("geog1" "public"."geography", "geog2" "public"."geography", "use_spheroid" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_distancecpa"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_distancecpa"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_distancecpa"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distancecpa"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_distancesphere"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_distancesphere"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_distancesphere"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distancesphere"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_distancesphere"("geom1" "public"."geometry", "geom2" "public"."geometry", "radius" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_distancesphere"("geom1" "public"."geometry", "geom2" "public"."geometry", "radius" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_distancesphere"("geom1" "public"."geometry", "geom2" "public"."geometry", "radius" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distancesphere"("geom1" "public"."geometry", "geom2" "public"."geometry", "radius" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_distancespheroid"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_distancespheroid"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_distancespheroid"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distancespheroid"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_distancespheroid"("geom1" "public"."geometry", "geom2" "public"."geometry", "public"."spheroid") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_distancespheroid"("geom1" "public"."geometry", "geom2" "public"."geometry", "public"."spheroid") TO "anon";
GRANT ALL ON FUNCTION "public"."st_distancespheroid"("geom1" "public"."geometry", "geom2" "public"."geometry", "public"."spheroid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_distancespheroid"("geom1" "public"."geometry", "geom2" "public"."geometry", "public"."spheroid") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dump"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dump"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_dump"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dump"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dumppoints"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dumppoints"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_dumppoints"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dumppoints"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dumprings"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dumprings"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_dumprings"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dumprings"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dumpsegments"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dumpsegments"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_dumpsegments"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dumpsegments"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dwithin"("text", "text", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dwithin"("text", "text", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_dwithin"("text", "text", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dwithin"("text", "text", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_dwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dwithin"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_dwithin"("geog1" "public"."geography", "geog2" "public"."geography", "tolerance" double precision, "use_spheroid" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_dwithin"("geog1" "public"."geography", "geog2" "public"."geography", "tolerance" double precision, "use_spheroid" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_dwithin"("geog1" "public"."geography", "geog2" "public"."geography", "tolerance" double precision, "use_spheroid" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_dwithin"("geog1" "public"."geography", "geog2" "public"."geography", "tolerance" double precision, "use_spheroid" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_endpoint"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_endpoint"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_endpoint"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_endpoint"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_envelope"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_envelope"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_envelope"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_envelope"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_equals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text", "text", boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text", "text", boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text", "text", boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_estimatedextent"("text", "text", "text", boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_expand"("public"."box2d", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."box2d", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."box2d", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."box2d", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_expand"("public"."box3d", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."box3d", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."box3d", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."box3d", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_expand"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_expand"("box" "public"."box2d", "dx" double precision, "dy" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_expand"("box" "public"."box2d", "dx" double precision, "dy" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"("box" "public"."box2d", "dx" double precision, "dy" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"("box" "public"."box2d", "dx" double precision, "dy" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_expand"("box" "public"."box3d", "dx" double precision, "dy" double precision, "dz" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_expand"("box" "public"."box3d", "dx" double precision, "dy" double precision, "dz" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"("box" "public"."box3d", "dx" double precision, "dy" double precision, "dz" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"("box" "public"."box3d", "dx" double precision, "dy" double precision, "dz" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_expand"("geom" "public"."geometry", "dx" double precision, "dy" double precision, "dz" double precision, "dm" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_expand"("geom" "public"."geometry", "dx" double precision, "dy" double precision, "dz" double precision, "dm" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_expand"("geom" "public"."geometry", "dx" double precision, "dy" double precision, "dz" double precision, "dm" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_expand"("geom" "public"."geometry", "dx" double precision, "dy" double precision, "dz" double precision, "dm" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_exteriorring"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_exteriorring"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_exteriorring"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_exteriorring"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_filterbym"("public"."geometry", double precision, double precision, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_filterbym"("public"."geometry", double precision, double precision, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_filterbym"("public"."geometry", double precision, double precision, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_filterbym"("public"."geometry", double precision, double precision, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_findextent"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_findextent"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_findextent"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_findextent"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_findextent"("text", "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_findextent"("text", "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_findextent"("text", "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_findextent"("text", "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_flipcoordinates"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_flipcoordinates"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_flipcoordinates"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_flipcoordinates"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_force2d"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_force2d"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_force2d"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_force2d"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_force3d"("geom" "public"."geometry", "zvalue" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_force3d"("geom" "public"."geometry", "zvalue" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_force3d"("geom" "public"."geometry", "zvalue" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_force3d"("geom" "public"."geometry", "zvalue" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_force3dm"("geom" "public"."geometry", "mvalue" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_force3dm"("geom" "public"."geometry", "mvalue" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_force3dm"("geom" "public"."geometry", "mvalue" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_force3dm"("geom" "public"."geometry", "mvalue" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_force3dz"("geom" "public"."geometry", "zvalue" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_force3dz"("geom" "public"."geometry", "zvalue" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_force3dz"("geom" "public"."geometry", "zvalue" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_force3dz"("geom" "public"."geometry", "zvalue" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_force4d"("geom" "public"."geometry", "zvalue" double precision, "mvalue" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_force4d"("geom" "public"."geometry", "zvalue" double precision, "mvalue" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_force4d"("geom" "public"."geometry", "zvalue" double precision, "mvalue" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_force4d"("geom" "public"."geometry", "zvalue" double precision, "mvalue" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_forcecollection"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_forcecollection"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcecollection"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcecollection"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_forcecurve"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_forcecurve"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcecurve"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcecurve"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_forcepolygonccw"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_forcepolygonccw"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcepolygonccw"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcepolygonccw"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_forcepolygoncw"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_forcepolygoncw"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcepolygoncw"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcepolygoncw"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_forcerhr"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_forcerhr"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcerhr"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcerhr"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_forcesfs"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_forcesfs"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcesfs"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcesfs"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_forcesfs"("public"."geometry", "version" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_forcesfs"("public"."geometry", "version" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_forcesfs"("public"."geometry", "version" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_forcesfs"("public"."geometry", "version" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_frechetdistance"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_frechetdistance"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_frechetdistance"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_frechetdistance"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_fromflatgeobuf"("anyelement", "bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_fromflatgeobuf"("anyelement", "bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_fromflatgeobuf"("anyelement", "bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_fromflatgeobuf"("anyelement", "bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_fromflatgeobuftotable"("text", "text", "bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_fromflatgeobuftotable"("text", "text", "bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_fromflatgeobuftotable"("text", "text", "bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_fromflatgeobuftotable"("text", "text", "bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_generatepoints"("area" "public"."geometry", "npoints" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_generatepoints"("area" "public"."geometry", "npoints" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_generatepoints"("area" "public"."geometry", "npoints" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_generatepoints"("area" "public"."geometry", "npoints" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_generatepoints"("area" "public"."geometry", "npoints" integer, "seed" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_generatepoints"("area" "public"."geometry", "npoints" integer, "seed" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_generatepoints"("area" "public"."geometry", "npoints" integer, "seed" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_generatepoints"("area" "public"."geometry", "npoints" integer, "seed" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geogfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geogfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geogfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geogfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geogfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geogfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geogfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geogfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geographyfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geographyfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geographyfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geographyfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geohash"("geog" "public"."geography", "maxchars" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geohash"("geog" "public"."geography", "maxchars" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geohash"("geog" "public"."geography", "maxchars" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geohash"("geog" "public"."geography", "maxchars" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geohash"("geom" "public"."geometry", "maxchars" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geohash"("geom" "public"."geometry", "maxchars" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geohash"("geom" "public"."geometry", "maxchars" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geohash"("geom" "public"."geometry", "maxchars" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomcollfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomcollfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geometricmedian"("g" "public"."geometry", "tolerance" double precision, "max_iter" integer, "fail_if_not_converged" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geometricmedian"("g" "public"."geometry", "tolerance" double precision, "max_iter" integer, "fail_if_not_converged" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geometricmedian"("g" "public"."geometry", "tolerance" double precision, "max_iter" integer, "fail_if_not_converged" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geometricmedian"("g" "public"."geometry", "tolerance" double precision, "max_iter" integer, "fail_if_not_converged" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geometryfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geometryfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geometryfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geometryfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geometryfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geometryfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geometryfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geometryfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geometryn"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geometryn"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geometryn"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geometryn"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geometrytype"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geometrytype"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geometrytype"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geometrytype"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromewkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromewkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromewkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromewkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromewkt"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromewkt"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromewkt"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromewkt"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromgeohash"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromgeohash"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgeohash"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgeohash"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(json) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(json) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(json) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"(json) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"("jsonb") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"("jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"("jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"("jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgeojson"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromgml"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromgml"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgml"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgml"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromgml"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromgml"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromgml"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromgml"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromkml"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromkml"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromkml"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromkml"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfrommarc21"("marc21xml" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfrommarc21"("marc21xml" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfrommarc21"("marc21xml" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfrommarc21"("marc21xml" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromtwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromtwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromtwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromtwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_geomfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_geomfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_geomfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_geomfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_gmltosql"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_gmltosql"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_gmltosql"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_gmltosql"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_gmltosql"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_gmltosql"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_gmltosql"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_gmltosql"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_hasarc"("geometry" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_hasarc"("geometry" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_hasarc"("geometry" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_hasarc"("geometry" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_hausdorffdistance"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_hexagon"("size" double precision, "cell_i" integer, "cell_j" integer, "origin" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_hexagon"("size" double precision, "cell_i" integer, "cell_j" integer, "origin" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_hexagon"("size" double precision, "cell_i" integer, "cell_j" integer, "origin" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_hexagon"("size" double precision, "cell_i" integer, "cell_j" integer, "origin" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_hexagongrid"("size" double precision, "bounds" "public"."geometry", OUT "geom" "public"."geometry", OUT "i" integer, OUT "j" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_hexagongrid"("size" double precision, "bounds" "public"."geometry", OUT "geom" "public"."geometry", OUT "i" integer, OUT "j" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_hexagongrid"("size" double precision, "bounds" "public"."geometry", OUT "geom" "public"."geometry", OUT "i" integer, OUT "j" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_hexagongrid"("size" double precision, "bounds" "public"."geometry", OUT "geom" "public"."geometry", OUT "i" integer, OUT "j" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_interiorringn"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_interiorringn"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_interiorringn"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_interiorringn"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_interpolatepoint"("line" "public"."geometry", "point" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_interpolatepoint"("line" "public"."geometry", "point" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_interpolatepoint"("line" "public"."geometry", "point" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_interpolatepoint"("line" "public"."geometry", "point" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_intersection"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_intersection"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersection"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersection"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_intersection"("public"."geography", "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_intersection"("public"."geography", "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersection"("public"."geography", "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersection"("public"."geography", "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_intersection"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_intersection"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersection"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersection"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_intersects"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_intersects"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersects"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersects"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_intersects"("geog1" "public"."geography", "geog2" "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_intersects"("geog1" "public"."geography", "geog2" "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersects"("geog1" "public"."geography", "geog2" "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersects"("geog1" "public"."geography", "geog2" "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_intersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_intersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_intersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_intersects"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isclosed"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isclosed"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_isclosed"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isclosed"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_iscollection"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_iscollection"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_iscollection"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_iscollection"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isempty"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isempty"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_isempty"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isempty"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_ispolygonccw"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_ispolygonccw"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_ispolygonccw"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ispolygonccw"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_ispolygoncw"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_ispolygoncw"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_ispolygoncw"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ispolygoncw"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isring"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isring"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_isring"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isring"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_issimple"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_issimple"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_issimple"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_issimple"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isvalid"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isvalid"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvalid"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvalid"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isvalid"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isvalid"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvalid"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvalid"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isvaliddetail"("geom" "public"."geometry", "flags" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isvaliddetail"("geom" "public"."geometry", "flags" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvaliddetail"("geom" "public"."geometry", "flags" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvaliddetail"("geom" "public"."geometry", "flags" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isvalidreason"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isvalidreason"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvalidreason"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvalidreason"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isvalidreason"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isvalidreason"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvalidreason"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvalidreason"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_isvalidtrajectory"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_isvalidtrajectory"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_isvalidtrajectory"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_isvalidtrajectory"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_length"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_length"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_length"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_length"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_length"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_length"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_length"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_length"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_length"("geog" "public"."geography", "use_spheroid" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_length"("geog" "public"."geography", "use_spheroid" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_length"("geog" "public"."geography", "use_spheroid" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_length"("geog" "public"."geography", "use_spheroid" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_length2d"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_length2d"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_length2d"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_length2d"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_length2dspheroid"("public"."geometry", "public"."spheroid") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_length2dspheroid"("public"."geometry", "public"."spheroid") TO "anon";
GRANT ALL ON FUNCTION "public"."st_length2dspheroid"("public"."geometry", "public"."spheroid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_length2dspheroid"("public"."geometry", "public"."spheroid") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_lengthspheroid"("public"."geometry", "public"."spheroid") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_lengthspheroid"("public"."geometry", "public"."spheroid") TO "anon";
GRANT ALL ON FUNCTION "public"."st_lengthspheroid"("public"."geometry", "public"."spheroid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_lengthspheroid"("public"."geometry", "public"."spheroid") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_letters"("letters" "text", "font" json) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_letters"("letters" "text", "font" json) TO "anon";
GRANT ALL ON FUNCTION "public"."st_letters"("letters" "text", "font" json) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_letters"("letters" "text", "font" json) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linecrossingdirection"("line1" "public"."geometry", "line2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linecrossingdirection"("line1" "public"."geometry", "line2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_linecrossingdirection"("line1" "public"."geometry", "line2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linecrossingdirection"("line1" "public"."geometry", "line2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linefromencodedpolyline"("txtin" "text", "nprecision" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linefromencodedpolyline"("txtin" "text", "nprecision" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefromencodedpolyline"("txtin" "text", "nprecision" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefromencodedpolyline"("txtin" "text", "nprecision" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linefrommultipoint"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linefrommultipoint"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefrommultipoint"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefrommultipoint"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linefromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linefromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linefromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linefromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linefromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linefromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linefromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linefromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linefromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linefromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoint"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoint"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoint"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoint"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoints"("public"."geometry", double precision, "repeat" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoints"("public"."geometry", double precision, "repeat" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoints"("public"."geometry", double precision, "repeat" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_lineinterpolatepoints"("public"."geometry", double precision, "repeat" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linelocatepoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linelocatepoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_linelocatepoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linelocatepoint"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linemerge"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linemerge"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_linemerge"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linemerge"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linemerge"("public"."geometry", boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linemerge"("public"."geometry", boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linemerge"("public"."geometry", boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linemerge"("public"."geometry", boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linestringfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linesubstring"("public"."geometry", double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linesubstring"("public"."geometry", double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_linesubstring"("public"."geometry", double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linesubstring"("public"."geometry", double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_linetocurve"("geometry" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_linetocurve"("geometry" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_linetocurve"("geometry" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_linetocurve"("geometry" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_locatealong"("geometry" "public"."geometry", "measure" double precision, "leftrightoffset" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_locatealong"("geometry" "public"."geometry", "measure" double precision, "leftrightoffset" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_locatealong"("geometry" "public"."geometry", "measure" double precision, "leftrightoffset" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_locatealong"("geometry" "public"."geometry", "measure" double precision, "leftrightoffset" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_locatebetween"("geometry" "public"."geometry", "frommeasure" double precision, "tomeasure" double precision, "leftrightoffset" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_locatebetween"("geometry" "public"."geometry", "frommeasure" double precision, "tomeasure" double precision, "leftrightoffset" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_locatebetween"("geometry" "public"."geometry", "frommeasure" double precision, "tomeasure" double precision, "leftrightoffset" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_locatebetween"("geometry" "public"."geometry", "frommeasure" double precision, "tomeasure" double precision, "leftrightoffset" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_locatebetweenelevations"("geometry" "public"."geometry", "fromelevation" double precision, "toelevation" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_locatebetweenelevations"("geometry" "public"."geometry", "fromelevation" double precision, "toelevation" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_locatebetweenelevations"("geometry" "public"."geometry", "fromelevation" double precision, "toelevation" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_locatebetweenelevations"("geometry" "public"."geometry", "fromelevation" double precision, "toelevation" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_longestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_longestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_longestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_longestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_m"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_m"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_m"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_m"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makebox2d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makebox2d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_makebox2d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makebox2d"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makeenvelope"(double precision, double precision, double precision, double precision, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makeenvelope"(double precision, double precision, double precision, double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makeenvelope"(double precision, double precision, double precision, double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makeenvelope"(double precision, double precision, double precision, double precision, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makeline"("public"."geometry"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makeline"("public"."geometry"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makeline"("public"."geometry"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makeline"("public"."geometry"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makeline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makeline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_makeline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makeline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepoint"(double precision, double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makepointm"(double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makepointm"(double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepointm"(double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepointm"(double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makepolygon"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makepolygon"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepolygon"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepolygon"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makepolygon"("public"."geometry", "public"."geometry"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makepolygon"("public"."geometry", "public"."geometry"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_makepolygon"("public"."geometry", "public"."geometry"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makepolygon"("public"."geometry", "public"."geometry"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makevalid"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makevalid"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_makevalid"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makevalid"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makevalid"("geom" "public"."geometry", "params" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makevalid"("geom" "public"."geometry", "params" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_makevalid"("geom" "public"."geometry", "params" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makevalid"("geom" "public"."geometry", "params" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_maxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_maxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_maxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_maxdistance"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_maximuminscribedcircle"("public"."geometry", OUT "center" "public"."geometry", OUT "nearest" "public"."geometry", OUT "radius" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_maximuminscribedcircle"("public"."geometry", OUT "center" "public"."geometry", OUT "nearest" "public"."geometry", OUT "radius" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_maximuminscribedcircle"("public"."geometry", OUT "center" "public"."geometry", OUT "nearest" "public"."geometry", OUT "radius" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_maximuminscribedcircle"("public"."geometry", OUT "center" "public"."geometry", OUT "nearest" "public"."geometry", OUT "radius" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_memsize"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_memsize"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_memsize"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_memsize"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_minimumboundingcircle"("inputgeom" "public"."geometry", "segs_per_quarter" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_minimumboundingcircle"("inputgeom" "public"."geometry", "segs_per_quarter" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_minimumboundingcircle"("inputgeom" "public"."geometry", "segs_per_quarter" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_minimumboundingcircle"("inputgeom" "public"."geometry", "segs_per_quarter" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_minimumboundingradius"("public"."geometry", OUT "center" "public"."geometry", OUT "radius" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_minimumboundingradius"("public"."geometry", OUT "center" "public"."geometry", OUT "radius" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_minimumboundingradius"("public"."geometry", OUT "center" "public"."geometry", OUT "radius" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_minimumboundingradius"("public"."geometry", OUT "center" "public"."geometry", OUT "radius" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_minimumclearance"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_minimumclearance"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_minimumclearance"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_minimumclearance"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_minimumclearanceline"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_minimumclearanceline"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_minimumclearanceline"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_minimumclearanceline"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mlinefromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mlinefromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_mlinefromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mlinefromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mlinefromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mlinefromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mlinefromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mlinefromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mlinefromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mpointfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mpointfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpointfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpointfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mpointfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mpointfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpointfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpointfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpointfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpolyfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_mpolyfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multi"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multi"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_multi"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multi"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multilinefromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multilinefromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_multilinefromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multilinefromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multilinestringfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multipointfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multipointfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipointfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipointfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipointfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipolyfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_multipolygonfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_ndims"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_ndims"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_ndims"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ndims"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_node"("g" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_node"("g" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_node"("g" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_node"("g" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_normalize"("geom" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_normalize"("geom" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_normalize"("geom" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_normalize"("geom" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_npoints"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_npoints"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_npoints"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_npoints"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_nrings"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_nrings"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_nrings"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_nrings"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_numgeometries"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_numgeometries"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_numgeometries"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_numgeometries"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_numinteriorring"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_numinteriorring"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_numinteriorring"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_numinteriorring"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_numinteriorrings"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_numinteriorrings"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_numinteriorrings"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_numinteriorrings"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_numpatches"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_numpatches"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_numpatches"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_numpatches"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_numpoints"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_numpoints"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_numpoints"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_numpoints"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_offsetcurve"("line" "public"."geometry", "distance" double precision, "params" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_offsetcurve"("line" "public"."geometry", "distance" double precision, "params" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_offsetcurve"("line" "public"."geometry", "distance" double precision, "params" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_offsetcurve"("line" "public"."geometry", "distance" double precision, "params" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_orderingequals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_orderingequals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_orderingequals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_orderingequals"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_orientedenvelope"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_orientedenvelope"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_orientedenvelope"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_orientedenvelope"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_overlaps"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_patchn"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_patchn"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_patchn"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_patchn"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_perimeter"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_perimeter"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_perimeter"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_perimeter"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_perimeter"("geog" "public"."geography", "use_spheroid" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_perimeter"("geog" "public"."geography", "use_spheroid" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_perimeter"("geog" "public"."geography", "use_spheroid" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_perimeter"("geog" "public"."geography", "use_spheroid" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_perimeter2d"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_perimeter2d"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_perimeter2d"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_perimeter2d"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision, "srid" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision, "srid" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision, "srid" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_point"(double precision, double precision, "srid" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointfromgeohash"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointfromgeohash"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointfromgeohash"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointfromgeohash"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointinsidecircle"("public"."geometry", double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointinsidecircle"("public"."geometry", double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointinsidecircle"("public"."geometry", double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointinsidecircle"("public"."geometry", double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointm"("xcoordinate" double precision, "ycoordinate" double precision, "mcoordinate" double precision, "srid" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointm"("xcoordinate" double precision, "ycoordinate" double precision, "mcoordinate" double precision, "srid" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointm"("xcoordinate" double precision, "ycoordinate" double precision, "mcoordinate" double precision, "srid" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointm"("xcoordinate" double precision, "ycoordinate" double precision, "mcoordinate" double precision, "srid" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointn"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointn"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointn"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointn"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointonsurface"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointonsurface"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointonsurface"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointonsurface"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_points"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_points"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_points"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_points"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointz"("xcoordinate" double precision, "ycoordinate" double precision, "zcoordinate" double precision, "srid" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointz"("xcoordinate" double precision, "ycoordinate" double precision, "zcoordinate" double precision, "srid" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointz"("xcoordinate" double precision, "ycoordinate" double precision, "zcoordinate" double precision, "srid" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointz"("xcoordinate" double precision, "ycoordinate" double precision, "zcoordinate" double precision, "srid" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_pointzm"("xcoordinate" double precision, "ycoordinate" double precision, "zcoordinate" double precision, "mcoordinate" double precision, "srid" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_pointzm"("xcoordinate" double precision, "ycoordinate" double precision, "zcoordinate" double precision, "mcoordinate" double precision, "srid" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_pointzm"("xcoordinate" double precision, "ycoordinate" double precision, "zcoordinate" double precision, "mcoordinate" double precision, "srid" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_pointzm"("xcoordinate" double precision, "ycoordinate" double precision, "zcoordinate" double precision, "mcoordinate" double precision, "srid" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polyfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polyfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_polyfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polyfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polyfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polyfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polyfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polyfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polyfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polyfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_polyfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polyfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polyfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polyfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polyfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polyfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polygon"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polygon"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygon"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygon"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polygonfromtext"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polygonfromtext"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonfromtext"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonfromtext"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polygonfromtext"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polygonfromtext"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonfromtext"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonfromtext"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"("bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"("bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"("bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"("bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"("bytea", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"("bytea", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"("bytea", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonfromwkb"("bytea", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polygonize"("public"."geometry"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polygonize"("public"."geometry"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonize"("public"."geometry"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonize"("public"."geometry"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_project"("geog" "public"."geography", "distance" double precision, "azimuth" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_project"("geog" "public"."geography", "distance" double precision, "azimuth" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_project"("geog" "public"."geography", "distance" double precision, "azimuth" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_project"("geog" "public"."geography", "distance" double precision, "azimuth" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_quantizecoordinates"("g" "public"."geometry", "prec_x" integer, "prec_y" integer, "prec_z" integer, "prec_m" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_quantizecoordinates"("g" "public"."geometry", "prec_x" integer, "prec_y" integer, "prec_z" integer, "prec_m" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_quantizecoordinates"("g" "public"."geometry", "prec_x" integer, "prec_y" integer, "prec_z" integer, "prec_m" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_quantizecoordinates"("g" "public"."geometry", "prec_x" integer, "prec_y" integer, "prec_z" integer, "prec_m" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_reduceprecision"("geom" "public"."geometry", "gridsize" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_reduceprecision"("geom" "public"."geometry", "gridsize" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_reduceprecision"("geom" "public"."geometry", "gridsize" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_reduceprecision"("geom" "public"."geometry", "gridsize" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_relate"("geom1" "public"."geometry", "geom2" "public"."geometry", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_relatematch"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_relatematch"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_relatematch"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_relatematch"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_removepoint"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_removepoint"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_removepoint"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_removepoint"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_removerepeatedpoints"("geom" "public"."geometry", "tolerance" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_removerepeatedpoints"("geom" "public"."geometry", "tolerance" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_removerepeatedpoints"("geom" "public"."geometry", "tolerance" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_removerepeatedpoints"("geom" "public"."geometry", "tolerance" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_reverse"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_reverse"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_reverse"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_reverse"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision, "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision, "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision, "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision, "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotate"("public"."geometry", double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_rotatex"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_rotatex"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotatex"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotatex"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_rotatey"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_rotatey"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotatey"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotatey"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_rotatez"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_rotatez"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_rotatez"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_rotatez"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", "public"."geometry", "origin" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", "public"."geometry", "origin" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", "public"."geometry", "origin" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", "public"."geometry", "origin" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_scale"("public"."geometry", double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_scroll"("public"."geometry", "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_scroll"("public"."geometry", "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_scroll"("public"."geometry", "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_scroll"("public"."geometry", "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_segmentize"("geog" "public"."geography", "max_segment_length" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_segmentize"("geog" "public"."geography", "max_segment_length" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_segmentize"("geog" "public"."geography", "max_segment_length" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_segmentize"("geog" "public"."geography", "max_segment_length" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_segmentize"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_segmentize"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_segmentize"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_segmentize"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_seteffectivearea"("public"."geometry", double precision, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_seteffectivearea"("public"."geometry", double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_seteffectivearea"("public"."geometry", double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_seteffectivearea"("public"."geometry", double precision, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_setpoint"("public"."geometry", integer, "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_setpoint"("public"."geometry", integer, "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_setpoint"("public"."geometry", integer, "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_setpoint"("public"."geometry", integer, "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_setsrid"("geog" "public"."geography", "srid" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_setsrid"("geog" "public"."geography", "srid" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_setsrid"("geog" "public"."geography", "srid" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_setsrid"("geog" "public"."geography", "srid" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_setsrid"("geom" "public"."geometry", "srid" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_setsrid"("geom" "public"."geometry", "srid" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_setsrid"("geom" "public"."geometry", "srid" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_setsrid"("geom" "public"."geometry", "srid" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_sharedpaths"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_sharedpaths"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_sharedpaths"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_sharedpaths"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_shiftlongitude"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_shiftlongitude"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_shiftlongitude"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_shiftlongitude"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_shortestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_shortestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_shortestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_shortestline"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_simplify"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_simplify"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_simplify"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_simplify"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_simplify"("public"."geometry", double precision, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_simplify"("public"."geometry", double precision, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_simplify"("public"."geometry", double precision, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_simplify"("public"."geometry", double precision, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_simplifypolygonhull"("geom" "public"."geometry", "vertex_fraction" double precision, "is_outer" boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_simplifypolygonhull"("geom" "public"."geometry", "vertex_fraction" double precision, "is_outer" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_simplifypolygonhull"("geom" "public"."geometry", "vertex_fraction" double precision, "is_outer" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_simplifypolygonhull"("geom" "public"."geometry", "vertex_fraction" double precision, "is_outer" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_simplifypreservetopology"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_simplifypreservetopology"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_simplifypreservetopology"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_simplifypreservetopology"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_simplifyvw"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_simplifyvw"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_simplifyvw"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_simplifyvw"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_snap"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_snap"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_snap"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_snap"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision, double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("public"."geometry", double precision, double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_snaptogrid"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision, double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_snaptogrid"("geom1" "public"."geometry", "geom2" "public"."geometry", double precision, double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_split"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_split"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_split"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_split"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_square"("size" double precision, "cell_i" integer, "cell_j" integer, "origin" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_square"("size" double precision, "cell_i" integer, "cell_j" integer, "origin" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_square"("size" double precision, "cell_i" integer, "cell_j" integer, "origin" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_square"("size" double precision, "cell_i" integer, "cell_j" integer, "origin" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_squaregrid"("size" double precision, "bounds" "public"."geometry", OUT "geom" "public"."geometry", OUT "i" integer, OUT "j" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_squaregrid"("size" double precision, "bounds" "public"."geometry", OUT "geom" "public"."geometry", OUT "i" integer, OUT "j" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_squaregrid"("size" double precision, "bounds" "public"."geometry", OUT "geom" "public"."geometry", OUT "i" integer, OUT "j" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_squaregrid"("size" double precision, "bounds" "public"."geometry", OUT "geom" "public"."geometry", OUT "i" integer, OUT "j" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_srid"("geog" "public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_srid"("geog" "public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_srid"("geog" "public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_srid"("geog" "public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_srid"("geom" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_srid"("geom" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_srid"("geom" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_srid"("geom" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_startpoint"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_startpoint"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_startpoint"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_startpoint"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_subdivide"("geom" "public"."geometry", "maxvertices" integer, "gridsize" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_subdivide"("geom" "public"."geometry", "maxvertices" integer, "gridsize" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_subdivide"("geom" "public"."geometry", "maxvertices" integer, "gridsize" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_subdivide"("geom" "public"."geometry", "maxvertices" integer, "gridsize" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_summary"("public"."geography") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_summary"("public"."geography") TO "anon";
GRANT ALL ON FUNCTION "public"."st_summary"("public"."geography") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_summary"("public"."geography") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_summary"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_summary"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_summary"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_summary"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_swapordinates"("geom" "public"."geometry", "ords" "cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_swapordinates"("geom" "public"."geometry", "ords" "cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."st_swapordinates"("geom" "public"."geometry", "ords" "cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_swapordinates"("geom" "public"."geometry", "ords" "cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_symdifference"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_symdifference"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_symdifference"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_symdifference"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_symmetricdifference"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_symmetricdifference"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_symmetricdifference"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_symmetricdifference"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_tileenvelope"("zoom" integer, "x" integer, "y" integer, "bounds" "public"."geometry", "margin" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_tileenvelope"("zoom" integer, "x" integer, "y" integer, "bounds" "public"."geometry", "margin" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_tileenvelope"("zoom" integer, "x" integer, "y" integer, "bounds" "public"."geometry", "margin" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_tileenvelope"("zoom" integer, "x" integer, "y" integer, "bounds" "public"."geometry", "margin" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_touches"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_touches"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_touches"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_touches"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_transform"("public"."geometry", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_transform"("public"."geometry", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_transform"("public"."geometry", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_transform"("public"."geometry", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "to_proj" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "to_proj" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "to_proj" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "to_proj" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "from_proj" "text", "to_srid" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "from_proj" "text", "to_srid" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "from_proj" "text", "to_srid" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "from_proj" "text", "to_srid" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "from_proj" "text", "to_proj" "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "from_proj" "text", "to_proj" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "from_proj" "text", "to_proj" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_transform"("geom" "public"."geometry", "from_proj" "text", "to_proj" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_translate"("public"."geometry", double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_translate"("public"."geometry", double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_translate"("public"."geometry", double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_translate"("public"."geometry", double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_translate"("public"."geometry", double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_translate"("public"."geometry", double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_translate"("public"."geometry", double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_translate"("public"."geometry", double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_transscale"("public"."geometry", double precision, double precision, double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_transscale"("public"."geometry", double precision, double precision, double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_transscale"("public"."geometry", double precision, double precision, double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_transscale"("public"."geometry", double precision, double precision, double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_triangulatepolygon"("g1" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_triangulatepolygon"("g1" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_triangulatepolygon"("g1" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_triangulatepolygon"("g1" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_unaryunion"("public"."geometry", "gridsize" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_unaryunion"("public"."geometry", "gridsize" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_unaryunion"("public"."geometry", "gridsize" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_unaryunion"("public"."geometry", "gridsize" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_union"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_union"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_union"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_union"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_union"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_union"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_union"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_union"("geom1" "public"."geometry", "geom2" "public"."geometry", "gridsize" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_voronoilines"("g1" "public"."geometry", "tolerance" double precision, "extend_to" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_voronoilines"("g1" "public"."geometry", "tolerance" double precision, "extend_to" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_voronoilines"("g1" "public"."geometry", "tolerance" double precision, "extend_to" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_voronoilines"("g1" "public"."geometry", "tolerance" double precision, "extend_to" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_voronoipolygons"("g1" "public"."geometry", "tolerance" double precision, "extend_to" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_voronoipolygons"("g1" "public"."geometry", "tolerance" double precision, "extend_to" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_voronoipolygons"("g1" "public"."geometry", "tolerance" double precision, "extend_to" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_voronoipolygons"("g1" "public"."geometry", "tolerance" double precision, "extend_to" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_within"("geom1" "public"."geometry", "geom2" "public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_wkbtosql"("wkb" "bytea") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_wkbtosql"("wkb" "bytea") TO "anon";
GRANT ALL ON FUNCTION "public"."st_wkbtosql"("wkb" "bytea") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_wkbtosql"("wkb" "bytea") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_wkttosql"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_wkttosql"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_wkttosql"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_wkttosql"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_wrapx"("geom" "public"."geometry", "wrap" double precision, "move" double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_wrapx"("geom" "public"."geometry", "wrap" double precision, "move" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_wrapx"("geom" "public"."geometry", "wrap" double precision, "move" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_wrapx"("geom" "public"."geometry", "wrap" double precision, "move" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_x"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_x"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_x"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_x"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_xmax"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_xmax"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."st_xmax"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_xmax"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_xmin"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_xmin"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."st_xmin"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_xmin"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_y"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_y"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_y"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_y"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_ymax"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_ymax"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."st_ymax"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ymax"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_ymin"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_ymin"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."st_ymin"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_ymin"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_z"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_z"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_z"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_z"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_zmax"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_zmax"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."st_zmax"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_zmax"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_zmflag"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_zmflag"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_zmflag"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_zmflag"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_zmin"("public"."box3d") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_zmin"("public"."box3d") TO "anon";
GRANT ALL ON FUNCTION "public"."st_zmin"("public"."box3d") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_zmin"("public"."box3d") TO "service_role";



GRANT ALL ON FUNCTION "public"."staging_area_geojson"("offer" "public"."load_offers") TO "anon";
GRANT ALL ON FUNCTION "public"."staging_area_geojson"("offer" "public"."load_offers") TO "authenticated";
GRANT ALL ON FUNCTION "public"."staging_area_geojson"("offer" "public"."load_offers") TO "service_role";



GRANT ALL ON FUNCTION "public"."start_trip"("p_shipment_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."start_trip"("p_shipment_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."start_trip"("p_shipment_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."submit_telemetry_event"("p_asset_id" "uuid", "p_recorded_by" "uuid", "p_event_type" "text", "p_payload" "jsonb", "p_client_timestamp" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."submit_telemetry_event"("p_asset_id" "uuid", "p_recorded_by" "uuid", "p_event_type" "text", "p_payload" "jsonb", "p_client_timestamp" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_telemetry_event"("p_asset_id" "uuid", "p_recorded_by" "uuid", "p_event_type" "text", "p_payload" "jsonb", "p_client_timestamp" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."sweep_stagnant_queues"() TO "anon";
GRANT ALL ON FUNCTION "public"."sweep_stagnant_queues"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sweep_stagnant_queues"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_asset_status_on_defect"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_asset_status_on_defect"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_asset_status_on_defect"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_watermelondb_push"("changes" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."sync_watermelondb_push"("changes" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_watermelondb_push"("changes" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."time_dist"(time without time zone, time without time zone) TO "postgres";
GRANT ALL ON FUNCTION "public"."time_dist"(time without time zone, time without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."time_dist"(time without time zone, time without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."time_dist"(time without time zone, time without time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_validate_dispatch"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_validate_dispatch"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_validate_dispatch"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_audit_compliance_doc"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_audit_compliance_doc"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_audit_compliance_doc"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_matchmaking_after_load_offer"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_matchmaking_after_load_offer"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_matchmaking_after_load_offer"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_ocr_auditor"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_ocr_auditor"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_ocr_auditor"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ts_dist"(timestamp without time zone, timestamp without time zone) TO "postgres";
GRANT ALL ON FUNCTION "public"."ts_dist"(timestamp without time zone, timestamp without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."ts_dist"(timestamp without time zone, timestamp without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."ts_dist"(timestamp without time zone, timestamp without time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."tstz_dist"(timestamp with time zone, timestamp with time zone) TO "postgres";
GRANT ALL ON FUNCTION "public"."tstz_dist"(timestamp with time zone, timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."tstz_dist"(timestamp with time zone, timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."tstz_dist"(timestamp with time zone, timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."unlockrows"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."unlockrows"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."unlockrows"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."unlockrows"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_project_geometry"("p_project_id" "uuid", "p_zone_type" "text", "p_geojson" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."update_project_geometry"("p_project_id" "uuid", "p_zone_type" "text", "p_geojson" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_project_geometry"("p_project_id" "uuid", "p_zone_type" "text", "p_geojson" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, character varying, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, character varying, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, character varying, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"(character varying, character varying, character varying, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."updategeometrysrid"("catalogn_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid_in" integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"("catalogn_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid_in" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"("catalogn_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid_in" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."updategeometrysrid"("catalogn_name" character varying, "schema_name" character varying, "table_name" character varying, "column_name" character varying, "new_srid_in" integer) TO "service_role";












GRANT ALL ON FUNCTION "public"."st_3dextent"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_3dextent"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_3dextent"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_3dextent"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement", boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement", boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement", boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement", boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement", boolean, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement", boolean, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement", boolean, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asflatgeobuf"("anyelement", boolean, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgeobuf"("anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgeobuf"("anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeobuf"("anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeobuf"("anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asgeobuf"("anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asgeobuf"("anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asgeobuf"("anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asgeobuf"("anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer, "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer, "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer, "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer, "text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer, "text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer, "text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_asmvt"("anyelement", "text", integer, "text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_clusterintersecting"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_clusterintersecting"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterintersecting"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterintersecting"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_clusterwithin"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_clusterwithin"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_clusterwithin"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_clusterwithin"("public"."geometry", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."st_collect"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_collect"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_collect"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_collect"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_extent"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_extent"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_extent"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_extent"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_makeline"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_makeline"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_makeline"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_makeline"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_memcollect"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_memcollect"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_memcollect"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_memcollect"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_memunion"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_memunion"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_memunion"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_memunion"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_polygonize"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_polygonize"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_polygonize"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_polygonize"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry") TO "postgres";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry") TO "anon";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry") TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry") TO "service_role";



GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."st_union"("public"."geometry", double precision) TO "service_role";















GRANT ALL ON TABLE "public"."asset_assignments" TO "anon";
GRANT ALL ON TABLE "public"."asset_assignments" TO "authenticated";
GRANT ALL ON TABLE "public"."asset_assignments" TO "service_role";



GRANT ALL ON TABLE "public"."asset_lockouts" TO "anon";
GRANT ALL ON TABLE "public"."asset_lockouts" TO "authenticated";
GRANT ALL ON TABLE "public"."asset_lockouts" TO "service_role";



GRANT ALL ON TABLE "public"."asset_telemetry_logs" TO "anon";
GRANT ALL ON TABLE "public"."asset_telemetry_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."asset_telemetry_logs" TO "service_role";



GRANT ALL ON TABLE "public"."assets" TO "anon";
GRANT ALL ON TABLE "public"."assets" TO "authenticated";
GRANT ALL ON TABLE "public"."assets" TO "service_role";



GRANT ALL ON TABLE "public"."assignments" TO "anon";
GRANT ALL ON TABLE "public"."assignments" TO "authenticated";
GRANT ALL ON TABLE "public"."assignments" TO "service_role";



GRANT ALL ON TABLE "public"."billing_contracts" TO "anon";
GRANT ALL ON TABLE "public"."billing_contracts" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_contracts" TO "service_role";



GRANT ALL ON TABLE "public"."billing_ledger" TO "anon";
GRANT ALL ON TABLE "public"."billing_ledger" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_ledger" TO "service_role";



GRANT ALL ON TABLE "public"."clients" TO "anon";
GRANT ALL ON TABLE "public"."clients" TO "authenticated";
GRANT ALL ON TABLE "public"."clients" TO "service_role";



GRANT ALL ON TABLE "public"."compliance_documents" TO "anon";
GRANT ALL ON TABLE "public"."compliance_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."compliance_documents" TO "service_role";



GRANT ALL ON TABLE "public"."cor_incidents" TO "anon";
GRANT ALL ON TABLE "public"."cor_incidents" TO "authenticated";
GRANT ALL ON TABLE "public"."cor_incidents" TO "service_role";



GRANT ALL ON TABLE "public"."cor_manifests" TO "anon";
GRANT ALL ON TABLE "public"."cor_manifests" TO "authenticated";
GRANT ALL ON TABLE "public"."cor_manifests" TO "service_role";



GRANT ALL ON TABLE "public"."dead_letter_queue" TO "anon";
GRANT ALL ON TABLE "public"."dead_letter_queue" TO "authenticated";
GRANT ALL ON TABLE "public"."dead_letter_queue" TO "service_role";



GRANT ALL ON TABLE "public"."driver_fatigue_evidence" TO "anon";
GRANT ALL ON TABLE "public"."driver_fatigue_evidence" TO "authenticated";
GRANT ALL ON TABLE "public"."driver_fatigue_evidence" TO "service_role";



GRANT ALL ON TABLE "public"."driver_licenses" TO "anon";
GRANT ALL ON TABLE "public"."driver_licenses" TO "authenticated";
GRANT ALL ON TABLE "public"."driver_licenses" TO "service_role";



GRANT ALL ON TABLE "public"."erp_outbox" TO "anon";
GRANT ALL ON TABLE "public"."erp_outbox" TO "authenticated";
GRANT ALL ON TABLE "public"."erp_outbox" TO "service_role";



GRANT ALL ON TABLE "public"."excavator_states" TO "anon";
GRANT ALL ON TABLE "public"."excavator_states" TO "authenticated";
GRANT ALL ON TABLE "public"."excavator_states" TO "service_role";



GRANT ALL ON TABLE "public"."execution_certificates" TO "anon";
GRANT ALL ON TABLE "public"."execution_certificates" TO "authenticated";
GRANT ALL ON TABLE "public"."execution_certificates" TO "service_role";



GRANT ALL ON TABLE "public"."expense_quarantine" TO "anon";
GRANT ALL ON TABLE "public"."expense_quarantine" TO "authenticated";
GRANT ALL ON TABLE "public"."expense_quarantine" TO "service_role";



GRANT ALL ON TABLE "public"."expenses" TO "anon";
GRANT ALL ON TABLE "public"."expenses" TO "authenticated";
GRANT ALL ON TABLE "public"."expenses" TO "service_role";



GRANT ALL ON TABLE "public"."fatigue_logs" TO "anon";
GRANT ALL ON TABLE "public"."fatigue_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."fatigue_logs" TO "service_role";



GRANT ALL ON TABLE "public"."fleet_billing_ledger" TO "anon";
GRANT ALL ON TABLE "public"."fleet_billing_ledger" TO "authenticated";
GRANT ALL ON TABLE "public"."fleet_billing_ledger" TO "service_role";



GRANT ALL ON TABLE "public"."fleet_invites" TO "anon";
GRANT ALL ON TABLE "public"."fleet_invites" TO "authenticated";
GRANT ALL ON TABLE "public"."fleet_invites" TO "service_role";



GRANT ALL ON TABLE "public"."fleets" TO "anon";
GRANT ALL ON TABLE "public"."fleets" TO "authenticated";
GRANT ALL ON TABLE "public"."fleets" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."fuel_logs" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."fuel_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."fuel_logs" TO "service_role";



GRANT ALL ON TABLE "public"."handover_logs" TO "anon";
GRANT ALL ON TABLE "public"."handover_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."handover_logs" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."haul_cycles" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."haul_cycles" TO "authenticated";
GRANT ALL ON TABLE "public"."haul_cycles" TO "service_role";



GRANT ALL ON TABLE "public"."invoices" TO "anon";
GRANT ALL ON TABLE "public"."invoices" TO "authenticated";
GRANT ALL ON TABLE "public"."invoices" TO "service_role";



GRANT ALL ON TABLE "public"."jit_active_queues" TO "anon";
GRANT ALL ON TABLE "public"."jit_active_queues" TO "authenticated";
GRANT ALL ON TABLE "public"."jit_active_queues" TO "service_role";



GRANT ALL ON TABLE "public"."license_categories" TO "anon";
GRANT ALL ON TABLE "public"."license_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."license_categories" TO "service_role";



GRANT ALL ON TABLE "public"."load_cycles" TO "anon";
GRANT ALL ON TABLE "public"."load_cycles" TO "authenticated";
GRANT ALL ON TABLE "public"."load_cycles" TO "service_role";



GRANT ALL ON TABLE "public"."maintenance_logs" TO "anon";
GRANT ALL ON TABLE "public"."maintenance_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."maintenance_logs" TO "service_role";



GRANT ALL ON TABLE "public"."maintenance_schedules" TO "anon";
GRANT ALL ON TABLE "public"."maintenance_schedules" TO "authenticated";
GRANT ALL ON TABLE "public"."maintenance_schedules" TO "service_role";



GRANT ALL ON TABLE "public"."master_orders" TO "anon";
GRANT ALL ON TABLE "public"."master_orders" TO "authenticated";
GRANT ALL ON TABLE "public"."master_orders" TO "service_role";



GRANT ALL ON TABLE "public"."materials" TO "anon";
GRANT ALL ON TABLE "public"."materials" TO "authenticated";
GRANT ALL ON TABLE "public"."materials" TO "service_role";



GRANT ALL ON TABLE "public"."mv_ato_fuel_rebate_ledger" TO "anon";
GRANT ALL ON TABLE "public"."mv_ato_fuel_rebate_ledger" TO "authenticated";
GRANT ALL ON TABLE "public"."mv_ato_fuel_rebate_ledger" TO "service_role";



GRANT ALL ON TABLE "public"."mv_daily_cycle_efficiency" TO "service_role";



GRANT ALL ON TABLE "public"."plant_defects" TO "anon";
GRANT ALL ON TABLE "public"."plant_defects" TO "authenticated";
GRANT ALL ON TABLE "public"."plant_defects" TO "service_role";



GRANT ALL ON TABLE "public"."mv_daily_fleet_downtime" TO "service_role";



GRANT ALL ON TABLE "public"."mv_daily_production_tonnage" TO "service_role";



GRANT ALL ON TABLE "public"."mv_predictive_maintenance_roster" TO "anon";
GRANT ALL ON TABLE "public"."mv_predictive_maintenance_roster" TO "authenticated";
GRANT ALL ON TABLE "public"."mv_predictive_maintenance_roster" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."shift_logs" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."shift_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."shift_logs" TO "service_role";



GRANT ALL ON TABLE "public"."mv_whs_compliance_audit" TO "anon";
GRANT ALL ON TABLE "public"."mv_whs_compliance_audit" TO "authenticated";
GRANT ALL ON TABLE "public"."mv_whs_compliance_audit" TO "service_role";



GRANT ALL ON TABLE "public"."nhvr_compliance_logs" TO "anon";
GRANT ALL ON TABLE "public"."nhvr_compliance_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."nhvr_compliance_logs" TO "service_role";



GRANT ALL ON TABLE "public"."nodes" TO "anon";
GRANT ALL ON TABLE "public"."nodes" TO "authenticated";
GRANT ALL ON TABLE "public"."nodes" TO "service_role";



GRANT ALL ON TABLE "public"."ocr_audit_logs" TO "anon";
GRANT ALL ON TABLE "public"."ocr_audit_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."ocr_audit_logs" TO "service_role";



GRANT ALL ON TABLE "public"."prestart_checks" TO "anon";
GRANT ALL ON TABLE "public"."prestart_checks" TO "authenticated";
GRANT ALL ON TABLE "public"."prestart_checks" TO "service_role";



GRANT ALL ON TABLE "public"."project_members" TO "anon";
GRANT ALL ON TABLE "public"."project_members" TO "authenticated";
GRANT ALL ON TABLE "public"."project_members" TO "service_role";



GRANT ALL ON TABLE "public"."project_sites" TO "anon";
GRANT ALL ON TABLE "public"."project_sites" TO "authenticated";
GRANT ALL ON TABLE "public"."project_sites" TO "service_role";



GRANT ALL ON TABLE "public"."projects" TO "anon";
GRANT ALL ON TABLE "public"."projects" TO "authenticated";
GRANT ALL ON TABLE "public"."projects" TO "service_role";



GRANT ALL ON TABLE "public"."role_audit_logs" TO "anon";
GRANT ALL ON TABLE "public"."role_audit_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."role_audit_logs" TO "service_role";



GRANT ALL ON TABLE "public"."routes" TO "anon";
GRANT ALL ON TABLE "public"."routes" TO "authenticated";
GRANT ALL ON TABLE "public"."routes" TO "service_role";



GRANT ALL ON TABLE "public"."secure_daily_cycle_efficiency" TO "anon";
GRANT ALL ON TABLE "public"."secure_daily_cycle_efficiency" TO "authenticated";
GRANT ALL ON TABLE "public"."secure_daily_cycle_efficiency" TO "service_role";



GRANT ALL ON TABLE "public"."secure_daily_fleet_downtime" TO "anon";
GRANT ALL ON TABLE "public"."secure_daily_fleet_downtime" TO "authenticated";
GRANT ALL ON TABLE "public"."secure_daily_fleet_downtime" TO "service_role";



GRANT ALL ON TABLE "public"."secure_daily_production_tonnage" TO "anon";
GRANT ALL ON TABLE "public"."secure_daily_production_tonnage" TO "authenticated";
GRANT ALL ON TABLE "public"."secure_daily_production_tonnage" TO "service_role";



GRANT ALL ON TABLE "public"."service_logs" TO "anon";
GRANT ALL ON TABLE "public"."service_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."service_logs" TO "service_role";



GRANT ALL ON TABLE "public"."shift_assignments" TO "anon";
GRANT ALL ON TABLE "public"."shift_assignments" TO "authenticated";
GRANT ALL ON TABLE "public"."shift_assignments" TO "service_role";



GRANT ALL ON TABLE "public"."sos_alerts" TO "anon";
GRANT ALL ON TABLE "public"."sos_alerts" TO "authenticated";
GRANT ALL ON TABLE "public"."sos_alerts" TO "service_role";



GRANT ALL ON TABLE "public"."structural_elements" TO "anon";
GRANT ALL ON TABLE "public"."structural_elements" TO "authenticated";
GRANT ALL ON TABLE "public"."structural_elements" TO "service_role";



GRANT ALL ON TABLE "public"."system_audit_logs" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."system_audit_logs" TO "authenticated";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."system_audit_logs" TO "service_role";



GRANT ALL ON TABLE "public"."system_config" TO "anon";
GRANT ALL ON TABLE "public"."system_config" TO "authenticated";
GRANT ALL ON TABLE "public"."system_config" TO "service_role";



GRANT ALL ON TABLE "public"."telemetry_dead_letter_logs" TO "anon";
GRANT ALL ON TABLE "public"."telemetry_dead_letter_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."telemetry_dead_letter_logs" TO "service_role";



GRANT ALL ON TABLE "public"."telemetry_inbox" TO "anon";
GRANT ALL ON TABLE "public"."telemetry_inbox" TO "authenticated";
GRANT ALL ON TABLE "public"."telemetry_inbox" TO "service_role";



GRANT ALL ON TABLE "public"."telemetry_logs" TO "anon";
GRANT ALL ON TABLE "public"."telemetry_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."telemetry_logs" TO "service_role";



GRANT ALL ON TABLE "public"."trip_waypoints" TO "anon";
GRANT ALL ON TABLE "public"."trip_waypoints" TO "authenticated";
GRANT ALL ON TABLE "public"."trip_waypoints" TO "service_role";



GRANT ALL ON TABLE "public"."trips" TO "anon";
GRANT ALL ON TABLE "public"."trips" TO "authenticated";
GRANT ALL ON TABLE "public"."trips" TO "service_role";



GRANT ALL ON TABLE "public"."vehicles" TO "anon";
GRANT ALL ON TABLE "public"."vehicles" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicles" TO "service_role";



GRANT ALL ON TABLE "public"."view_cor_audit_timeline" TO "anon";
GRANT ALL ON TABLE "public"."view_cor_audit_timeline" TO "authenticated";
GRANT ALL ON TABLE "public"."view_cor_audit_timeline" TO "service_role";



GRANT ALL ON TABLE "public"."view_driver_fatigue" TO "anon";
GRANT ALL ON TABLE "public"."view_driver_fatigue" TO "authenticated";
GRANT ALL ON TABLE "public"."view_driver_fatigue" TO "service_role";



GRANT ALL ON TABLE "public"."view_fleet_matrix" TO "anon";
GRANT ALL ON TABLE "public"."view_fleet_matrix" TO "authenticated";
GRANT ALL ON TABLE "public"."view_fleet_matrix" TO "service_role";



GRANT ALL ON TABLE "public"."view_project_progress" TO "anon";
GRANT ALL ON TABLE "public"."view_project_progress" TO "authenticated";
GRANT ALL ON TABLE "public"."view_project_progress" TO "service_role";



GRANT ALL ON TABLE "public"."view_site_bottlenecks" TO "anon";
GRANT ALL ON TABLE "public"."view_site_bottlenecks" TO "authenticated";
GRANT ALL ON TABLE "public"."view_site_bottlenecks" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."whs_prestart_logs" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."whs_prestart_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."whs_prestart_logs" TO "service_role";



GRANT ALL ON TABLE "public"."vw_daily_billable_assets" TO "anon";
GRANT ALL ON TABLE "public"."vw_daily_billable_assets" TO "authenticated";
GRANT ALL ON TABLE "public"."vw_daily_billable_assets" TO "service_role";



GRANT ALL ON TABLE "public"."webhook_endpoints" TO "anon";
GRANT ALL ON TABLE "public"."webhook_endpoints" TO "authenticated";
GRANT ALL ON TABLE "public"."webhook_endpoints" TO "service_role";



GRANT ALL ON TABLE "public"."webhook_events" TO "anon";
GRANT ALL ON TABLE "public"."webhook_events" TO "authenticated";
GRANT ALL ON TABLE "public"."webhook_events" TO "service_role";



GRANT ALL ON TABLE "public"."whs_overrides" TO "anon";
GRANT ALL ON TABLE "public"."whs_overrides" TO "authenticated";
GRANT ALL ON TABLE "public"."whs_overrides" TO "service_role";



GRANT ALL ON TABLE "public"."whs_prestarts" TO "anon";
GRANT ALL ON TABLE "public"."whs_prestarts" TO "authenticated";
GRANT ALL ON TABLE "public"."whs_prestarts" TO "service_role";









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































