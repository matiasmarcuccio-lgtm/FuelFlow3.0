import { createClient } from '@supabase/supabase-js';
import assert from 'assert';

const SUPABASE_URL = process.env.SUPABASE_URL || 'http://127.0.0.1:54321';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;

if (!SUPABASE_SERVICE_KEY || !SUPABASE_ANON_KEY) {
    console.error("Missing SUPABASE_SERVICE_ROLE_KEY or SUPABASE_ANON_KEY");
    process.exit(1);
}

// 1. Cliente Admin (Para inyectar aserciones sin RLS)
const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
// 2. Cliente Restringido (Para asalto RLS y disparos de supervisor)
const operatorClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

const delay = (ms) => new Promise(res => setTimeout(res, ms));

async function runTests() {
    console.log("🔥 Iniciando Batería de Pruebas de Integración Automatizada (OCR) 🔥\n");

    // Pre-requisito: Autenticar al cliente restringido como el Supervisor
    const { data: authData, error: authError } = await operatorClient.auth.signInWithPassword({
        email: 'supervisor@jitsite.com',
        password: 'password123'
    });
    if (authError) throw new Error(`Auth fallida: ${authError.message}`);
    const supervisorId = authData.user.id;
    
    // Buscar el ID del conductor (operator)
    const { data: opData } = await adminClient.from('profiles').select('id').eq('role', 'operator').limit(1).single();
    const driverId = opData.id;

    console.log(`[Setup] Supervisor autenticado: ${supervisorId}`);
    console.log(`[Setup] Conductor objetivo: ${driverId}\n`);

    // =================================================================================
    // Vector 1: Fraude Deliberado (random/meme)
    // =================================================================================
    console.log("==> Vector 1: Simulando Fraude (fake_document_random.jpg)");
    
    // Subir archivo dummy para que createSignedUrl no falle en Deno
    const dummyBlob1 = new Blob(["fake data"], { type: "image/jpeg" });
    const { error: uploadErr1 } = await adminClient.storage.from('compliance_docs').upload('fake_document_random.jpg', dummyBlob1, { upsert: true });
    if(uploadErr1) console.error("Upload error 1:", uploadErr1);

    const { error: rpcErr1 } = await operatorClient.rpc('fn_verify_driver_insurance', {
        p_driver_id: driverId,
        p_expiry_date: '2030-01-01',
        p_file_path: 'fake_document_random.jpg'
    });
    assert.strictEqual(rpcErr1, null, "El supervisor debió poder desbloquear transaccionalmente");
    
    await delay(3000); // Esperar que Deno procese asíncronamente

    // Validar con adminClient (Auditando silenciosamente)
    const { data: wo1 } = await adminClient.from('whs_overrides').select('id').eq('document_path', 'fake_document_random.jpg').order('override_timestamp', { ascending: false }).limit(1).single();
    const { data: log1 } = await adminClient.from('ocr_audit_logs')
        .select('*').eq('override_id', wo1.id).single();
    
    assert.ok(log1, "El log de auditoría 1 no se generó");
    assert.strictEqual(log1.is_fraud_flagged, true, "is_fraud_flagged debe ser TRUE");
    assert.strictEqual(log1.detected_document_type, 'UNKNOWN_IMAGE', "Debe detectar imagen desconocida");
    console.log("✅ Vector 1 superado: Fraude interceptado y auditado asíncronamente.\n");

    // =================================================================================
    // Vector 2: Falla Técnica (MIME Hostil - HEIC)
    // =================================================================================
    console.log("==> Vector 2: Simulando Falla Técnica / HEIC (camera_upload.heic)");
    
    const dummyBlob2 = new Blob(["fake heic"], { type: "image/jpeg" });
    const { error: uploadErr2 } = await adminClient.storage.from('compliance_docs').upload('camera_upload.heic', dummyBlob2, { upsert: true });
    if(uploadErr2) console.error("Upload error 2:", uploadErr2);

    await operatorClient.rpc('fn_verify_driver_insurance', {
        p_driver_id: driverId,
        p_expiry_date: '2030-01-01',
        p_file_path: 'camera_upload.heic'
    });
    
    await delay(3000);

    const { data: wo2 } = await adminClient.from('whs_overrides').select('id').eq('document_path', 'camera_upload.heic').order('override_timestamp', { ascending: false }).limit(1).single();
    const { data: log2 } = await adminClient.from('ocr_audit_logs')
        .select('*').eq('override_id', wo2.id).single();
    
    assert.ok(log2, "El log de auditoría 2 no se generó");
    assert.strictEqual(log2.is_fraud_flagged, false, "HEIC no es fraude delictivo, is_fraud_flagged = FALSE");
    assert.strictEqual(log2.detected_document_type, 'UNSUPPORTED_MIME', "Debe capturar UNSUPPORTED_MIME");
    console.log("✅ Vector 2 superado: Error técnico encapsulado sin falsas alarmas.\n");

    // =================================================================================
    // Vector 3: Ataque RLS (Intento de Destrucción Forense)
    // =================================================================================
    console.log("==> Vector 3: Asalto RLS (Intentar borrar el log de fraude usando token del supervisor)");
    
    const { error: deleteErr } = await operatorClient.from('ocr_audit_logs')
        .delete().eq('id', log1.id);
    
    // Dependiendo de Supabase, un DELETE sin RLS produce código 401/403 o no elimina filas (count = 0) silenciosamente
    // Vamos a forzar la aserción de que la fila SIGUE EXISTIENDO
    const { data: checkLog1 } = await adminClient.from('ocr_audit_logs').select('id').eq('id', log1.id).single();
    assert.ok(checkLog1, "¡BRECHA DE SEGURIDAD! El supervisor logró borrar su propio registro forense.");
    
    // Intento de UPDATE
    const { error: updateErr } = await operatorClient.from('whs_overrides')
        .update({ new_expiry_date: '2099-01-01' }).eq('id', log1.override_id);
    
    const { data: checkWo1 } = await adminClient.from('whs_overrides').select('new_expiry_date').eq('id', log1.override_id).single();
    assert.strictEqual(checkWo1.new_expiry_date, '2030-01-01', "¡BRECHA DE SEGURIDAD! El supervisor alteró un override sellado.");
    console.log("✅ Vector 3 superado: Inmutabilidad RLS garantizada matemáticamente. Las filas sobrevivieron el asalto.\n");

    // =================================================================================
    // Vector 4: Auditor del Auditor (Evasión de Deno + Sweeper)
    // =================================================================================
    console.log("==> Vector 4: Simulando Colapso de Deno y desencadenando el Sweeper");
    // Inyectamos un override directamente como admin y le falseamos el timestamp a hace 16 minutos
    const { data: orphanWo } = await adminClient.from('whs_overrides').insert({
        supervisor_id: supervisorId,
        driver_id: driverId,
        document_path: 'silence_crash.jpg',
        new_expiry_date: '2030-01-01',
        override_timestamp: new Date(Date.now() - 16 * 60000).toISOString()
    }).select().single();

    // Disparamos el sweeper de pg_cron manualmente (simulando que pasaron los 5 minutos)
    await adminClient.rpc('audit_the_ocr_auditor');

    // Afirmación: El sweeper debió inyectar un evento crítico en la Dead Letter Queue
    const { data: dlqEntry } = await adminClient.from('dead_letter_queue')
        .select('*').eq('original_event_id', orphanWo.id).single();
    
    assert.ok(dlqEntry, "El Sweeper no inyectó la alerta en la DLQ tras la evasión");
    assert.strictEqual(dlqEntry.event_type, 'OCR_AUDIT_EVASION');
    console.log("✅ Vector 4 superado: Sweeper interceptó exitosamente el fallo silencioso.\n");

    console.log("🎯 Todos los vectores forenses fueron superados. La arquitectura es inmutable y resiliente.");
}

runTests().catch(e => {
    console.error("❌ Falla crítica en pruebas de integración:");
    console.error(e);
    process.exit(1);
});
