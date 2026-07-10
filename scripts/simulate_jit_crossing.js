import { createClient } from '@supabase/supabase-js';

const supabaseUrl = 'http://127.0.0.1:54321';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

const supabase = createClient(supabaseUrl, supabaseKey);

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

async function runSimulation() {
    console.log('🚛 Iniciando simulación JIT Matching Engine...');
    
    // 1. Obtener o crear el proyecto de Hobart
    const projectId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    console.log(`📌 Proyecto Target: ${projectId}`);

    // 2. Asegurar que haya un camión activo
    let { data: trucks, error: truckErr } = await supabase
        .from('assets')
        .select('id, asset_type')
        .eq('current_project_id', projectId)
        .eq('asset_type', 'haul_truck')
        .limit(1);


    const { data: profiles } = await supabase.from('profiles').select('id').limit(1);
    const fleetManagerId = profiles?.[0]?.id || '00000000-0000-0000-0000-000000000000';

    if (!trucks || trucks.length === 0) {
        console.log('Insertando camión simulado...');

        const { data: newTrucks, error: insertError } = await supabase
            .from('assets')
            .insert({
                asset_code: 'TRK-SIM',
                registration_number: 'SIM-999',
                fleet_manager_id: fleetManagerId,
                current_project_id: projectId,
                asset_type: 'haul_truck',
                status: 'in_use',
                is_compliant: true
            })
            .select('id, asset_type');
            
        if (insertError) {
            console.error('Error inserting truck:', insertError);
            process.exit(1);
        }
        trucks = newTrucks;
    }
    
    const truck1 = trucks[0].id;
    console.log(`🚚 Camión seleccionado: ${truck1}`);

    // Coordenadas simuladas para el cargadero de Hobart (Aprox: -42.8850, 147.3250)
    // T1: Fuera del cargadero
    // T2: Dentro del cargadero
    // T3: Saliendo del cargadero

    const route = [
        { lat: -42.8870, lng: 147.3230, heading: 45, status: 'in_site', desc: 'Fuera (Aproximando)' },
        { lat: -42.8855, lng: 147.3245, heading: 45, status: 'in_site', desc: 'Cruzando Geovalla Estricta (Entrando)' },
        { lat: -42.8850, lng: 147.3250, heading: 90, status: 'in_site', desc: 'En el Cargadero (Esperando)' },
        { lat: -42.8845, lng: 147.3260, heading: 120, status: 'in_site', desc: 'En el Cargadero (Cargando)' },
        { lat: -42.8830, lng: 147.3280, heading: 135, status: 'in_site', desc: 'Saliendo Geovalla Buffered (Despachando otro)' }
    ];

    for (let i = 0; i < route.length; i++) {
        const point = route[i];
        console.log(`\n📍 Paso ${i+1}: ${point.desc}`);
        
        const payload = {
            asset_id: truck1,
            recorded_by: fleetManagerId, // System / Fleet Manager
            event_type: 'spatial_ping',
            payload: {
                status: point.status,
                project_id: projectId,
                category: 'haul_truck',
                location: {
                    lat: point.lat,
                    lng: point.lng,
                    heading: point.heading,
                    speed: i === 2 || i === 3 ? 0 : 25,
                    timestamp: new Date().toISOString()
                }
            },
            client_timestamp: new Date().toISOString()
        };

        const { error } = await supabase.from('asset_telemetry_logs').insert({
            asset_id: payload.asset_id,
            recorded_by: payload.recorded_by,
            event_type: payload.event_type,
            payload: payload.payload,
            client_timestamp: payload.client_timestamp
        });

        if (error) {
            console.error('❌ Error inyectando telemetría:', error.message);
        } else {
            console.log(`✅ Telemetría inyectada [${point.lat}, ${point.lng}] H:${point.heading}`);
        }

        // Verificamos la cola transaccional
        const { data: queue } = await supabase
            .from('jit_active_queues')
            .select('*')
            .eq('project_id', projectId);
            
        console.log('📋 Estado de la Cola JIT:', queue);

        await sleep(3000); // 3 segundos entre pings
    }

    console.log('\n🏁 Simulación completada.');
}

runSimulation();
