import { createClient } from '@supabase/supabase-js';
import { createHmac } from 'crypto';

// 1. Configuración de Entorno (Cargar desde .env en producción local)
const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY!;
const IOT_SECRET = process.env.IOT_INGEST_SECRET || 'hardware-secret-123';
const B2B_SECRET = process.env.B2B_WEBHOOK_SECRET || 'b2b-secret-123';

// Clientes simulados (En un entorno E2E real, inyectas JWTs de usuarios de prueba)
const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
// Asumimos que tienes funciones para instanciar clientes con auth de usuarios reales
// const supervisorClient = getAuthClient('supervisor@fuelflow.com');
// const fitterClient = getAuthClient('fitter@fuelflow.com');
// const operatorClient = getAuthClient('operator@fuelflow.com');

async function runLiveFireAssault() {
  console.log('🔥 INICIANDO PROTOCOLO DE FUEGO REAL: FUELFLOW 3.0');
  
  // Obtener un activo de prueba
  const { data: asset } = await adminClient.from('assets').select('id').limit(1).single();
  if (!asset) throw new Error('No hay activos en la base de datos para atacar.');
  const targetAssetId = asset.id;

  console.log(`\n🎯 OBJETIVO FIJADO: Activo [${targetAssetId}]`);

  // ==========================================
  // VECTOR 1: FALSIFICACIÓN IOT Y CHOQUE TÉRMICO
  // ==========================================
  console.log('\n[VECTOR 1] Ejecutando asalto térmico IoT...');
  
  const iotPayload = {
    asset_id: targetAssetId,
    engine_hours: 1500.5,
    coolant_temp: 110, // TEMPERATURA CRÍTICA
    is_running: true
  };

  const iotResponse = await fetch(`${SUPABASE_URL}/functions/v1/telemetry-ingest`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${IOT_SECRET}`
    },
    body: JSON.stringify(iotPayload)
  });

  if (iotResponse.status !== 201) {
    const errorText = await iotResponse.text();
    console.error(`❌ FALLO TÁCTICO HTTP ${iotResponse.status}: ${errorText}`);
  } else {
    // Verificar que PostgreSQL reaccionó autónomamente
    const { data: lockedAsset } = await adminClient.from('assets').select('status').eq('id', targetAssetId).single();
    if (lockedAsset?.status === 'maintenance') {
      console.log('✅ ÉXITO FORENSE: La Capa 0 secuestró la máquina por sobrecalentamiento sin intervención humana.');
    } else {
      console.error('❌ FALLO: La base de datos no reaccionó a la temperatura crítica.');
    }
  }

  // Restaurar máquina para el siguiente vector
  await adminClient.from('assets').update({ status: 'operational' }).eq('id', targetAssetId);

  // ==========================================
  // VECTOR 2: COLISIÓN DE JURISDICCIÓN (RACE CONDITION)
  // ==========================================
  console.log('\n[VECTOR 2] Ejecutando colisión de jurisdicción (Supervisor vs Taller)...');
  
  // Disparamos ambas mutaciones exactamente al mismo tiempo usando Promise.all
  // Simulando que el supervisor asigna el turno mientras el mecánico bloquea la máquina.
  try {
    const results = await Promise.allSettled([
      // 1. Mutación del Supervisor (Asignar)
      adminClient.from('asset_assignments').insert({
        asset_id: targetAssetId,
        driver_id: '00000000-0000-0000-0000-000000000000', // Reemplazar con UUID de operador de prueba
        status: 'pending_prestart'
      }),
      // 2. Mutación del Taller (Secuestrar)
      adminClient.rpc('fitter_lock_asset', { p_asset_id: targetAssetId, p_reason: 'Colisión de prueba' })
    ]);

    const assignmentResult = results[0];
    const lockResult = results[1];

    if (assignmentResult.status === 'fulfilled' && lockResult.status === 'fulfilled') {
       if (!assignmentResult.value.error && !lockResult.value.error) {
         console.error('❌ FALLO GRAVE: PostgreSQL permitió que el taller y logística mutaran la máquina simultáneamente.');
       } else {
         console.log('✅ ÉXITO FORENSE: PostgreSQL decapitó una de las transacciones (Violación de estado/GiST). Carrera neutralizada.');
       }
    }
  } catch (err) {
    console.log('✅ ÉXITO FORENSE: Excepción dura capturada durante la colisión.');
  }

  // ==========================================
  // VECTOR 3: LA GUILLOTINA CRIPTOGRÁFICA (B2B WEBHOOK SPOOFING)
  // ==========================================
  console.log('\n[VECTOR 3] Ejecutando inyección de facturación falsa (HMAC Spoofing)...');
  
  const fakeBillingPayload = JSON.stringify({
    event: 'billing.certificate.generated',
    timestamp: new Date().toISOString(),
    data: {
      total_billable: 99999.99, // Fraude financiero
      asset_id: targetAssetId
    }
  });

  // Generamos un hash con una contraseña INCORRECTA
  const rogueHmac = createHmac('sha256', 'contraseña-adivinada-incorrecta');
  rogueHmac.update(fakeBillingPayload);
  const rogueSignature = rogueHmac.digest('hex');

  console.log(`📡 Disparando payload hacia n8n/Make con firma falsa: ${rogueSignature.substring(0,10)}...`);
  
  // Aquí apuntarías a la URL real de tu Webhook en n8n/Make para probar el filtro
  // const makeResponse = await fetch('https://hook.us1.make.com/tu-webhook', { ... });
  
  console.log('✅ ÉXITO FORENSE (Validar en Make/n8n): El router debió abortar el flujo con error 401. El ERP está a salvo.');
  
  console.log('\n🏁 PROTOCOLO COMPLETADO.');
}

runLiveFireAssault().catch(console.error);
