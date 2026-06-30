import { createClient } from '@supabase/supabase-js';

// Local Supabase defaults (Standard across all default local CLI projects)
const SUPABASE_URL = 'http://127.0.0.1:54321';
const localAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRlZmF1bHQiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTYwOTQ1OTIwMCwiZXhwIjoxOTI1MDk1MjAwfQ.x-ZtPWeR2-jE-RzWfI9mYnL4uA4tX00x1e3QjR0h0lE';

const supabase = createClient(SUPABASE_URL, localAnonKey);

async function injectChaos() {
  console.log('🌪️ INITIATING CHAOS INJECTION PROTOCOL...');

  // 1. Fetch 15 available trips to infect
  const { data: offers, error: fetchError } = await supabase
    .from('load_offers')
    .select('id')
    .limit(15);

  if (fetchError || !offers || offers.length < 15) {
    console.error('Failed to fetch 15 load offers to infect. Please ensure DB is seeded. Error:', fetchError?.message || 'Not enough offers');
    return;
  }

  const promises = [];

  // 5 BREAKDOWNS
  for (let i = 0; i < 5; i++) {
    const offerId = offers[i].id;
    promises.push(
      supabase.from('load_offers').update({
        status: 'BREAKDOWN'
      }).eq('id', offerId).then(() => console.log(`[BREAKDOWN] Injected into ${offerId}`))
    );
  }

  // 5 EMERGENCY OVERRIDES
  for (let i = 5; i < 10; i++) {
    const offerId = offers[i].id;
    promises.push(
      supabase.from('load_offers').update({
        status: 'IN_TRANSIT',
        anomaly_flag: 'DRIVER_EMERGENCY_OVERRIDE'
      }).eq('id', offerId).then(() => console.log(`[OVERRIDE] Injected into ${offerId}`))
    );
  }

  // 5 MASS MISMATCHES (Triggered by ending in 9 via the DB trigger)
  for (let i = 10; i < 15; i++) {
    const offerId = offers[i].id;
    promises.push(
      supabase.from('load_offers').update({
        status: 'IN_TRANSIT',
        loaded_gross_mass: 48009, // Ends in 9 triggers the 'MASS_MISMATCH' in simulate_docket_ocr
        docket_image_path: 'mock_chaos_image.jpg'
      }).eq('id', offerId).then(() => console.log(`[MASS_MISMATCH] Injected into ${offerId}`))
    );
  }

  console.log('Firing 15 concurrent mutations...');
  
  const start = Date.now();
  await Promise.all(promises);
  const end = Date.now();

  console.log(`💀 CHAOS INJECTED SUCCESSFULLY in ${end - start}ms.`);
  console.log('Check the Web Command Center. The Fleet Manager should be sweating.');
}

injectChaos();
