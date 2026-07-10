import http from 'k6/http';
import { check, sleep } from 'k6';
import { fail } from 'k6';

import { SharedArray } from 'k6/data';

const SUPABASE_URL = __ENV.SUPABASE_URL || 'http://127.0.0.1:54321';
const SUPABASE_ANON_KEY = __ENV.SUPABASE_ANON_KEY;

if (!SUPABASE_ANON_KEY) {
    fail('SUPABASE_ANON_KEY environment variable is required');
}

// Cargar los JWTs estáticos generados previamente
const users = new SharedArray('users', function () {
    const data = JSON.parse(open('./tokens.json'));
    return data;
});

export const options = {
    scenarios: {
        morning_rush: {
            executor: 'ramping-vus',
            startVUs: 0,
            stages: [
                { duration: '10s', target: 50 }, // Ramp up to 50 trucks arriving
                { duration: '30s', target: 50 }, // Sustained load
                { duration: '10s', target: 0 },  // Ramp down
            ],
        },
    },
    thresholds: {
        // Tolerancia estricta: 95% de las peticiones deben resolverse en menos de 250ms
        http_req_duration: ['p(95)<250'],
        // 0% de errores permitidos (No deadlocks, no 409, no 5xx)
        http_req_failed: ['rate==0'],
    },
};

export function setup() {
    console.log(`Setup completo: ${users.length} VUs listos para el asedio usando tokens estáticos.`);
    if (users.length === 0) {
        fail('No se cargaron los usuarios desde tokens.json');
    }
    return users; // Pasado al default(data)
}

export default function () {
    // k6 __VU is 1-indexed. We map it to our users array safely.
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

    // 1. Paso A: Acercamiento (Fuera de la geovalla)
    const payloadOutside = JSON.stringify({
        asset_id: user.asset_id,
        recorded_by: user.userId,
        event_type: 'location_update',
        client_timestamp: new Date().toISOString(),
        payload: {
            location: {
                lat: -42.8870, // Fuera del polígono
                lng: 147.3255,
                heading: 0,
                speed: 15
            }
        }
    });

    let res = http.post(`${SUPABASE_URL}/rest/v1/asset_telemetry_logs`, payloadOutside, params);
    check(res, { 'Outside Insert OK': (r) => r.status === 201 });

    // Jitter estocástico para simular latencia de red LTE (100ms - 2000ms)
    sleep(Math.random() * 1.9 + 0.1);

    // 2. Paso B: Impacto Transaccional (Dentro de la geovalla estricta)
    const payloadInside = JSON.stringify({
        asset_id: user.asset_id,
        recorded_by: user.userId,
        event_type: 'location_update',
        client_timestamp: new Date().toISOString(),
        payload: {
            location: {
                lat: -42.8850, // Dentro del polígono estricto (gatilla ST_Contains y la cascada FIFO)
                lng: 147.3255,
                heading: 0,
                speed: 5
            }
        }
    });

    let res2 = http.post(`${SUPABASE_URL}/rest/v1/asset_telemetry_logs`, payloadInside, params);
    
    check(res2, {
        'Inside Insert OK': (r) => r.status === 201,
        'No Deadlocks (409/5xx)': (r) => r.status !== 409 && r.status < 500,
    });

    sleep(1);
}
