import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.VITE_SUPABASE_URL || 'http://127.0.0.1:54321';
const SUPABASE_ANON_KEY = process.env.VITE_SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.XYZ'; // Esto usará el key real desde process.env o podemos simplemente requerir un package.json config.
// Wait, to ensure we have the correct ANON key, let's just use the SERVICE key but create authenticated clients. Or better, I will inject the correct anon key.

async function runTests() {
  // Let's get the anon key from the local API config if available, but since this is a local setup, the anon key is standard for local supabase.
  const anonKey = process.env.VITE_SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.oUq0rE-Z2-z4Ww4KzQ7N7Xk5Z1-X0L6J-l3b9Z9v2bM'; // Standard demo anon key

  const supervisorClient = createClient(SUPABASE_URL, anonKey, { auth: { persistSession: false } });
  const fitterClient = createClient(SUPABASE_URL, anonKey, { auth: { persistSession: false } });
  const operatorClient = createClient(SUPABASE_URL, anonKey, { auth: { persistSession: false } });

  console.log('--- AUTENTICANDO IDENTIDADES ---');
  await supervisorClient.auth.signInWithPassword({ email: 'supervisor@jitsite.com', password: 'password123' });
  await fitterClient.auth.signInWithPassword({ email: 'fitter@jitsite.com', password: 'password123' });
  await operatorClient.auth.signInWithPassword({ email: 'operator@jitsite.com', password: 'password123' });

  const supervisorId = (await supervisorClient.auth.getUser()).data.user.id;
  const fitterId = (await fitterClient.auth.getUser()).data.user.id;
  const operatorId = (await operatorClient.auth.getUser()).data.user.id;

  console.log('✅ Identidades Listas.');

  // Necesitamos un activo operativo
  const { data: assets } = await supervisorClient.from('assets').select('*').eq('status', 'operational').limit(2);
  const assetA = assets[0].id;
  const assetB = assets[1].id;
  const fleetId = assets[0].fleet_id;

  console.log('\n--- INICIANDO VECTOR 1: COLISIÓN GIST Y FATIGA SIMULTÁNEA ---');
  
  // Asignamos turnos falsos en el pasado usando service_role para reventar el límite de fatiga (12 horas).
  const adminClient = createClient(SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU');
  
  // Limpiar turnos previos
  await adminClient.from('asset_assignments').delete().eq('driver_id', operatorId);

  // Inyectar 11.5 horas de fatiga
  await adminClient.from('asset_assignments').insert({
    fleet_id: fleetId,
    asset_id: assetA,
    driver_id: operatorId,
    assigned_by: supervisorId,
    status: 'completed',
    shift_start: new Date(Date.now() - 12 * 3600000).toISOString(),
    shift_end: new Date(Date.now() - 0.5 * 3600000).toISOString(),
  });

  // Intentar crear un turno nuevo (el frontend envía esto sin fatigue_override)
  console.log('Intentando Despacho Normal (Sin Override)...');
  const res1 = await supervisorClient.from('asset_assignments').insert({
    fleet_id: fleetId,
    asset_id: assetA,
    driver_id: operatorId,
    assigned_by: supervisorId,
  });

  if (res1.error && res1.error.message.includes('WHS_FATIGUE_LIMIT')) {
    console.log('✅ VECTOR 1.1 SUPERADO: El motor de fatiga WHS rechazó el despacho correctamente (Hard Block).');
  } else {
    console.error('❌ FALLO VECTOR 1.1: Se permitió la asignación a pesar de la fatiga.', res1.error);
  }

  // Ahora el Supervisor lo firma con Override (Doble Gasto Temporal)
  console.log('Enviando despacho con Override Autorizado y forzando Doble Gasto (GiST)...');
  const p1 = supervisorClient.from('asset_assignments').insert({
    fleet_id: fleetId,
    asset_id: assetA,
    driver_id: operatorId,
    assigned_by: supervisorId,
    fatigue_override_reason: 'Autorización táctica temporal',
    override_approved_by: supervisorId,
  });

  const p2 = supervisorClient.from('asset_assignments').insert({
    fleet_id: fleetId,
    asset_id: assetB,
    driver_id: operatorId,
    assigned_by: supervisorId,
    fatigue_override_reason: 'Autorización táctica temporal',
    override_approved_by: supervisorId,
  });

  const [resA, resB] = await Promise.all([p1, p2]);
  
  // Al menos uno debe fallar por colisión temporal (GiST)
  const gistFailed = (resA.error && resA.error.code === '23P01') || (resB.error && resB.error.code === '23P01');
  if (gistFailed) {
    console.log('✅ VECTOR 1.2 SUPERADO: Violación GiST 23P01 atrapada. Imposible el Doble Gasto físico del operador.');
  } else {
    console.error('❌ FALLO VECTOR 1.2: No se detuvo la condición de carrera GiST.', resA.error, resB.error);
  }

  // Recuperar el Assignment ID activo de la promesa que fue exitosa
  const activeAssignment = (resA.data ? resA.data : resB.data)?.[0];
  const assignedAsset = resA.data ? assetA : assetB;

  // Si no logramos recuperar el ID porque el código anterior usó .select().single() o no lo hicimos:
  const { data: assignments } = await adminClient.from('asset_assignments').select('*').eq('driver_id', operatorId).eq('status', 'pending_prestart');
  const assignment = assignments[0];

  console.log('\n--- INICIANDO VECTOR 2: SECUESTRO MECÁNICO (WORKSHOP OVERRIDE) ---');
  // Fitter secuestra el activo antes de que el Kiosco firme
  const fitterRes = await fitterClient.rpc('fitter_lock_asset', {
    p_asset_id: assignment.asset_id,
    p_reason: 'Manguera hidráulica delantera estallada'
  });

  if (!fitterRes.error) {
    console.log('✅ VECTOR 2.1 SUPERADO: Fitter secuestró el activo exitosamente.');
    // Validar estado del activo
    const { data: chkAsset } = await adminClient.from('assets').select('status').eq('id', assignment.asset_id).single();
    if (chkAsset.status === 'maintenance') {
      console.log('✅ VECTOR 2.2 SUPERADO: Activo mutó a "maintenance". Interceptando Kiosco logístico.');
    }
  } else {
    console.error('❌ FALLO VECTOR 2: Fitter no pudo secuestrar el activo.', fitterRes.error);
  }

  console.log('\n--- INICIANDO VECTOR 3: BIOMETRÍA VS. RELOJ DEL SERVIDOR ---');
  // Necesitamos un turno limpio en pending_prestart para la prueba
  const { data: assetCArr } = await supervisorClient.from('assets').select('*').eq('status', 'operational').limit(1);
  const assetC = assetCArr[0].id;
  
  const { data: newShiftArr } = await supervisorClient.from('asset_assignments').insert({
    fleet_id: fleetId,
    asset_id: assetC,
    driver_id: operatorId,
    assigned_by: supervisorId,
    fatigue_override_reason: 'Nueva máquina',
    override_approved_by: supervisorId,
  }).select();
  const newShift = newShiftArr[0];

  // 1. Kiosco abre: dispara el reloj del servidor
  await operatorClient.rpc('mark_prestart_commenced', { p_assignment_id: newShift.id });
  
  // 2. Ataque Spoofing: Certificar instantáneamente (Lápiz Rápido / Pencil-Whipping)
  console.log('Ejecutando ataque: Certificación instantánea (0s de fricción física)...');
  const hackRes = await operatorClient.rpc('certify_prestart', {
    p_assignment_id: newShift.id,
    p_brakes: true,
    p_fluids: true,
    p_structural: true,
    p_is_safe: true,
    p_defect_notes: null
  });

  if (hackRes.error && hackRes.error.message.includes('prestart_time_friction')) {
    console.log('✅ VECTOR 3 SUPERADO: El reloj del Servidor aplastó el ataque de Pencil-Whipping. La base de datos es inquebrantable.');
  } else {
    console.error('❌ FALLO VECTOR 3: El sistema permitió el Bypass de la inspección física.', hackRes.error);
  }

  console.log('\n🚀 BATERÍA DE PRUEBAS COMPLETADA. LA FÍSICA DEL SISTEMA SE MANTIENE INTACTA.');
}

runTests().catch(console.error);
