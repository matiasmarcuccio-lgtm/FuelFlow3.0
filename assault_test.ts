import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3';

// 1. Configuración del Entorno (Inyecta tus credenciales locales)
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || 'http://127.0.0.1:54321';
// Usa la ANON_KEY local (puede extraerse del output de supabase start)
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

// Credenciales del Supervisor de Prueba
const SUPERVISOR_EMAIL = 'admin@jitsite.com'; 
const SUPERVISOR_PASSWORD = 'password123';

// IDs pre-forjados que debes tener en tu base de datos para la prueba
const MOCK_FLEET_ID = '48432f69-952e-4536-bd5a-095a3d2bb8cf';
const MOCK_ASSET_ID = '55555555-5555-5555-5555-555555555555';
const MOCK_ASSET_NO_LIC_ID = '66666666-6666-6666-6666-666666666666'; // Requiere licencia LV, pero el driver tiene HR
const MOCK_DRIVER_ID = '22222222-2222-2222-2222-222222222222';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function runAssault() {
  console.log("Iniciando Asalto Forense al Motor de Despacho...\n");

  // 1. Romper la Aduana (Autenticación para inyectar claims financieros)
  const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
    email: SUPERVISOR_EMAIL,
    password: SUPERVISOR_PASSWORD,
  });

  if (authError) {
    console.error("Fallo Catastrófico de Autenticación:", authError.message);
    return;
  }
  
  console.log(`[OK] Sesión establecida. JWT Inyectado para ${authData.user.email}`);

  // 2. Definir la carga útil base
  const baseAssignment = {
    fleet_id: MOCK_FLEET_ID,
    asset_id: MOCK_ASSET_ID,
    driver_id: MOCK_DRIVER_ID,
    assigned_by: authData.user.id,
    shift_start: new Date().toISOString(), // Turno inicia ahora
    shift_end: null, // Turno abierto (hasta el infinito)
  };

  // --- ESCENARIO 1: COLISIÓN DE ACTIVOS (Matemática GiST) ---
  console.log("\n--- Asalto 1: Colisión de Activos ---");
  // Intentar superponer a otro conductor en la misma máquina AHORA.
  // Nota: Ya hemos insertado un turno anterior en seed, pero ese terminó hace 1 hora.
  // Insertaremos un turno legítimo AHORA para el conductor, que chocará con la regla de fatiga si no le pasamos override.
  // Pero espera, el asalto 1 quiere probar colisión de activos.
  // Primero necesitamos un turno activo (shift_end = null) con un override para saltar la fatiga.
  
  const { error: insertLegitError } = await supabase.from('asset_assignments').insert([{
    ...baseAssignment,
    fatigue_override_reason: "Justificando la fatiga para poder abrir el turno base",
    override_approved_by: authData.user.id
  }]);
  
  if (insertLegitError) {
      console.error("[ERROR PREVIO] No se pudo insertar el turno base:", insertLegitError);
  }

  // Intentar superponer a otro conductor en la misma máquina AHORA
  const { error: collisionError } = await supabase.from('asset_assignments').insert([{
    ...baseAssignment,
    driver_id: '11111111-1111-1111-1111-111111111111', // Conductor B (Admin)
    fatigue_override_reason: "Override para ignorar fatiga del conductor B"
  }]);

  if (collisionError && collisionError.code === '23P01') {
    console.log("[PASS] PostgreSQL bloqueó la colisión espacio-tiempo del Activo (GiST Exclude).");
  } else {
    console.error("[FAIL] Brecha temporal detectada. El motor permitió la colisión.", collisionError);
  }

  // --- ESCENARIO 2: NEGLIGENCIA LEGAL (Licencia Faltante/Vencida) ---
  console.log("\n--- Asalto 2: Negligencia Legal (Licencias WHS) ---");
  const { error: licenseError } = await supabase.from('asset_assignments').insert([{
    fleet_id: MOCK_FLEET_ID,
    asset_id: MOCK_ASSET_NO_LIC_ID, // Máquina LV, el conductor tiene HR
    driver_id: MOCK_DRIVER_ID,
    assigned_by: authData.user.id,
    shift_start: new Date(Date.now() + 86400000).toISOString(), // Mañana, para no chocar con GiST
  }]);

  if (licenseError && licenseError.code === 'P0001' && licenseError.message.includes('WHS_INVALID_LICENSE')) {
    console.log("[PASS] Trigger WHS abortó el despacho. El conductor no tiene la licencia requerida.");
  } else {
    console.error("[FAIL] Brecha legal. Se asignó maquinaria a operador sin licencia o error inesperado.", licenseError);
  }

  // --- ESCENARIO 3: BLOQUEO DE FATIGA CIEGO ---
  console.log("\n--- Asalto 3: Muro de Fatiga (Sin justificación) ---");
  // Nota: Para que esto falle, el conductor debe tener > 12h en base de datos.
  // Ya inyectamos un turno de 13h en las últimas 24h a través de seed_test_data.sql.
  const { error: fatigueError } = await supabase.from('asset_assignments').insert([{
    ...baseAssignment,
    shift_start: new Date(Date.now() + 86400000 * 2).toISOString(), // Pasado mañana para no chocar GiST
    shift_end: new Date(Date.now() + 86400000 * 2 + 3600000).toISOString(), // Turno de 1 hora
  }]);

  if (fatigueError && fatigueError.code === 'P0001' && fatigueError.message.includes('WHS_FATIGUE_LIMIT')) {
    console.log("[PASS] Trigger abortó el despacho. Límite de fatiga excedido sin justificación.");
  } else {
    console.error("[FAIL] El motor ignoró el sumatorio de horas.", fatigueError);
  }

  // --- ESCENARIO 4: EL MURO PERMEABLE (Excepción Auditada) ---
  console.log("\n--- Asalto 4: Excepción de Fatiga (Delegación de Responsabilidad) ---");
  const { data: overrideData, error: overrideError } = await supabase.from('asset_assignments').insert([{
    ...baseAssignment,
    shift_start: new Date(Date.now() + 86400000 * 3).toISOString(), // En 3 días para no chocar
    shift_end: new Date(Date.now() + 86400000 * 3 + 3600000).toISOString(),
    fatigue_override_reason: "Emergencia operativa estructural autorizada por gerencia.",
    override_approved_by: authData.user.id
  }]).select();

  if (!overrideError && overrideData) {
    console.log("[PASS] Muro permeable cruzado exitosamente. Sello forense estampado en la base de datos.");
  } else {
    console.error("[FAIL] El sistema rechazó una excepción de fatiga válida.", overrideError);
  }
}

runAssault();
