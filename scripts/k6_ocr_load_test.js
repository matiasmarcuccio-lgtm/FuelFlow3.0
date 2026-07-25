import http from 'k6/http';
import { check, fail } from 'k6';
import { SharedArray } from 'k6/data';

const SUPABASE_URL = __ENV.SUPABASE_URL || 'http://127.0.0.1:54321';
const SUPABASE_ANON_KEY = __ENV.SUPABASE_ANON_KEY;

if (!SUPABASE_ANON_KEY) {
    fail('SUPABASE_ANON_KEY environment variable is required');
}

// Usamos el token de un supervisor extraído previamente o generado al vuelo para la prueba
const users = new SharedArray('users', function () {
    return JSON.parse(open('./tokens.json'));
});

export const options = {
    scenarios: {
        thundering_herd_ocr: {
            executor: 'shared-iterations',
            vus: 200, 
            iterations: 2500,
            maxDuration: '30s',
        },
    },
    thresholds: {
        // La estampida va a saturar la cola de pg_net, pero el RPC debe aguantar
        http_req_failed: ['rate==0'], 
        // Tolerancia a lentitud debido al asedio asíncrono
        http_req_duration: ['p(95)<4000'], 
    },
};

export function setup() {
    console.log(`[Thundering Herd - OCR] Armando asedio asíncrono para asfixiar pg_net...`);
    const supervisorToken = __ENV.SUPERVISOR_TOKEN;
    if (!supervisorToken) fail('SUPERVISOR_TOKEN env var is required');
    
    const driverId = __ENV.DRIVER_ID;
    if (!driverId) fail('DRIVER_ID env var is required');
    
    return { supervisorToken: supervisorToken, driverId: driverId };
}

export default function (data) {
    const params = {
        headers: {
            'Content-Type': 'application/json',
            'apikey': SUPABASE_ANON_KEY,
            'Authorization': `Bearer ${data.supervisorToken}`,
            'Prefer': 'return=minimal'
        },
    };

    // Lanzar ráfaga de validaciones OCR para asfixiar pg_net y probar el backoff y DLQ
    const rpcPayload = JSON.stringify({
        p_driver_id: data.driverId,
        p_expiry_date: '2030-01-01',
        p_file_path: `thundering_herd_${__ITER}.jpg`
    });

    const res = http.post(`${SUPABASE_URL}/rest/v1/rpc/fn_verify_driver_insurance`, rpcPayload, params);
    
    if (res.status !== 200 && res.status !== 204 && res.status !== 201) {
        console.log(`Failed with status ${res.status}: ${res.body}`);
    }

    check(res, { 
        'RPC OCR Accepted (200 OK)': (r) => r.status === 200 || r.status === 204 || r.status === 201 
    });
}
