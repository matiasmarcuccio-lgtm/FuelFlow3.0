import http from 'k6/http';
import { check, fail } from 'k6';
import { SharedArray } from 'k6/data';

const SUPABASE_URL = __ENV.SUPABASE_URL || 'http://127.0.0.1:54321';
const SUPABASE_ANON_KEY = __ENV.SUPABASE_ANON_KEY;

if (!SUPABASE_ANON_KEY) {
    fail('SUPABASE_ANON_KEY environment variable is required');
}

// Cargar los JWTs generados de los operadores
const users = new SharedArray('users', function () {
    return JSON.parse(open('./tokens.json'));
});

export const options = {
    scenarios: {
        thundering_herd: {
            executor: 'per-vu-iterations',
            // Simular 30 camiones recuperando señal simultáneamente
            vus: 30, 
            // Cada camión volcará 50 ciclos retenidos y 1 solicitud de desbloqueo mecánico
            iterations: 1, 
            maxDuration: '30s',
        },
    },
    thresholds: {
        // La estampida causará contención en PostgreSQL, pero no deben haber errores 5xx o 409
        http_req_failed: ['rate==0'], 
        // 95% de las mutaciones concurrentes deben sobrevivir en < 3500ms bajo estrés masivo
        http_req_duration: ['p(95)<3500'], 
    },
};

export function setup() {
    console.log(`[Thundering Herd] Armando asedio con ${users.length} operadores...`);
    if (users.length === 0) fail('No se cargaron los usuarios desde tokens.json');
    return users;
}

export default function () {
    const userIndex = (__VU - 1) % users.length;
    const user = users[userIndex];

    const params = {
        headers: {
            'Content-Type': 'application/json',
            'apikey': SUPABASE_ANON_KEY,
            'Authorization': `Bearer ${user.token}`,
            'Prefer': 'return=minimal'
        },
    };

    // 1. Volcar Outbox de Telemetría (50 ciclos acumulados offline)
    // Se despachan en ráfaga (for loop) simulando a TanStack Query vaciando el caché
    let batchReqs = [];
    for (let i = 0; i < 50; i++) {
        const payload = JSON.stringify({
            asset_id: user.asset_id,
            recorded_by: user.userId,
            event_type: 'load_cycle_complete',
            client_timestamp: new Date().toISOString(),
            payload: { status: 'completed', tonnage: Math.floor(Math.random() * 50) + 20 }
        });
        
        batchReqs.push({
            method: 'POST',
            url: `${SUPABASE_URL}/rest/v1/asset_telemetry_logs`,
            body: payload,
            params: params
        });
    }

    // Ejecutar ráfaga masiva (1500 requests simultáneos en total por los 30 VUs)
    const responses = http.batch(batchReqs);
    responses.forEach(res => {
        check(res, { 'Outbox telemetry insert OK': (r) => r.status === 201 });
    });

    // 2. Volcar Intención de Desbloqueo Mecánico (RPC Offline)
    // El operador envía el PIN que digitó el mecánico 2 horas atrás en la cabina
    const rpcPayload = JSON.stringify({
        p_defect_id: '00000000-0000-0000-0000-000000000000', // Mock UUID para que Postgres responda
        p_category: 'wear_and_tear',
        p_resolution_notes: 'Thundering Herd Dump',
        p_mechanic_id: user.userId, 
        p_mechanic_pin: '1234'
    });

    let resRpc = http.post(`${SUPABASE_URL}/rest/v1/rpc/resolve_plant_defect`, rpcPayload, params);
    
    check(resRpc, { 'RPC Thundering Herd OK (No timeout/503)': (r) => r.status !== 503 && r.status !== 504 && r.status !== 502 });
}
