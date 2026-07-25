-- ============================================================================
-- ESCUDO ZERO-TRUST: ROW-LEVEL SECURITY (RLS) PARA CAPA 0
-- ============================================================================

-- 1. ACTIVACIÓN FORZOSA DE RLS EN EL 100% DE LAS TABLAS OPERATIVAS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shift_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.haul_cycles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fuel_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whs_prestart_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asset_lockouts ENABLE ROW LEVEL SECURITY;
-- 2. FUNCIÓN AUXILIAR DE ALTO RENDIMIENTO PARA EXTRAER EL FLEET_ID DEL JWT / PERFIL
-- Se marca como STABLE para que PostgreSQL la caché por consulta y no golpee la tabla profiles 10,000 veces
CREATE OR REPLACE FUNCTION public.fn_get_caller_fleet_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT fleet_id FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$$;

-- ============================================================================
-- POLÍTICAS DE LECTURA (SELECT): AISLAMIENTO DE TENENCIA MÚLTIPLE (TENANT ISOLATION)
-- Ningún usuario puede ver registros, camiones o rutas de otra minera rival en Hobart.
-- ============================================================================

-- PERFILES: Un operario ve su propio perfil; los gerentes ven a toda su flota
CREATE POLICY "rls_profiles_select_policy" ON public.profiles
FOR SELECT USING (
    id = auth.uid() 
    OR 
    fleet_id = public.fn_get_caller_fleet_id()
);

-- ACTIVOS (MAQUINARIA): Solo visible si pertenece a la flota del usuario autenticado
CREATE POLICY "rls_assets_select_policy" ON public.assets
FOR SELECT USING (
    fleet_id = public.fn_get_caller_fleet_id()
);

-- RUTAS Y MATERIALES: Catálogos visibles en lectura para toda la flota asignada
CREATE POLICY "rls_routes_select_policy" ON public.routes
FOR SELECT USING (fleet_id = public.fn_get_caller_fleet_id());

CREATE POLICY "rls_materials_select_policy" ON public.materials
FOR SELECT USING (fleet_id = public.fn_get_caller_fleet_id());

-- BITÁCORAS Y LIBROS MAYORES (TURNOS, ACARREO, COMBUSTIBLE, PRESTART, LOCKOUTS, MANTENIMIENTO)
-- Lectura estrictamente confinada al fleet_id del operador o gerente
CREATE POLICY "rls_shift_logs_select_policy" ON public.shift_logs
FOR SELECT USING (fleet_id = public.fn_get_caller_fleet_id());

CREATE POLICY "rls_haul_cycles_select_policy" ON public.haul_cycles
FOR SELECT USING (fleet_id = public.fn_get_caller_fleet_id());

CREATE POLICY "rls_fuel_logs_select_policy" ON public.fuel_logs
FOR SELECT USING (fleet_id = public.fn_get_caller_fleet_id());

CREATE POLICY "rls_whs_prestart_logs_select_policy" ON public.whs_prestart_logs
FOR SELECT USING (fleet_id = public.fn_get_caller_fleet_id());

CREATE POLICY "rls_asset_lockouts_select_policy" ON public.asset_lockouts
FOR SELECT USING (fleet_id = public.fn_get_caller_fleet_id());

-- ============================================================================
-- GUILLOTINA DE MUTACIÓN DIRECTA: BLOQUEO DE INSERT, UPDATE Y DELETE DESDE REST
-- Al NO definir políticas de INSERT/UPDATE/DELETE para 'authenticated' o 'anon',
-- PostgreSQL aplica un "DEFAULT DENY" (Denegación por Defecto).
-- Nadie puede modificar una tabla desde el frontend usando el SDK de Supabase.
-- Toda mutación DEBE pasar por los procedimientos fn_execute_shift_action, 
-- fn_execute_haul_transition, fn_submit_fuel_log, etc., que corren con autoridad de servidor.
-- ============================================================================
