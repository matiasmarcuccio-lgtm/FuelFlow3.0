import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || 'http://127.0.0.1:54321';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY!;

const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

async function injectLiveFireAmmunition() {
  console.log('📦 INYECTANDO TOPOLOGÍA DE ASALTO...');

  let proj = (await adminClient.from('projects').select().limit(1).single()).data;
  if (!proj) {
    const res = await adminClient.from('projects').insert({ name: 'Live Fire Project', status: 'active' }).select().single();
    proj = res.data;
    if (res.error) throw new Error(`Fallo en Proyecto: ${res.error.message}`);
  }

  let flt = (await adminClient.from('fleets').select().eq('name', 'Alpha Fleet').limit(1).single()).data;
  if (!flt) {
    const res = await adminClient.from('fleets').insert({ name: 'Alpha Fleet' }).select().single();
    flt = res.data;
    if (res.error) throw new Error(`Fallo en Flota: ${res.error.message}`);
  }

  let lic = (await adminClient.from('license_categories').select().eq('code', 'HR').limit(1).single()).data;
  if (!lic) {
    const res = await adminClient.from('license_categories').insert({ code: 'HR', description: 'Heavy Rigid' }).select().single();
    lic = res.data;
    if (res.error) throw new Error(`Fallo en Licencia: ${res.error.message}`);
  }

  let asset = (await adminClient.from('assets').select().eq('internal_code', 'DUMP-999').limit(1).single()).data;
  if (!asset) {
    const res = await adminClient.from('assets').insert({ 
      fleet_id: flt.id, 
      internal_code: 'DUMP-999', 
      category: 'heavy_machinery', 
      status: 'operational',
      current_engine_hours: 1500.0,
      required_license_id: lic.id
    }).select().single();
    asset = res.data;
    if (res.error) throw new Error(`Fallo en Activo: ${res.error.message}`);
  }

  const { data: contract } = await adminClient.from('billing_contracts').select().eq('asset_id', asset.id).limit(1).single();
  if (!contract) {
    const cE = await adminClient.from('billing_contracts').insert({
      asset_id: asset.id,
      model: 'wet_hire',
      hourly_rate_asset: 150.00,
      hourly_rate_operator: 55.00,
      overtime_threshold_hours: 10.00,
      overtime_multiplier: 1.50,
      currency: 'AUD'
    });
    if (cE.error) throw new Error(`Fallo en Contrato: ${cE.error.message}`);
  }

  console.log(`✅ Munición inyectada. Objetivo fijado: [${asset.id}]`);
  console.log('🔥 PROCEDE A DETONAR EL PROTOCOLO DE FUEGO REAL.');
}

injectLiveFireAmmunition().catch(console.error);
