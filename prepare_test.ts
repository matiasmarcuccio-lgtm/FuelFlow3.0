import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3';

const SUPABASE_URL = 'http://127.0.0.1:54321';
const SERVICE_ROLE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

async function prepare() {
  console.log("Preparando entorno de prueba...");

  // 1. Crear Usuario Supervisor
  const { data: authData, error: authError } = await supabase.auth.admin.createUser({
    email: 'admin@jitsite.com',
    password: 'password123',
    email_confirm: true,
  });

  if (authError && authError.message !== 'User already registered') {
    console.error("Error creando admin:", authError);
    return;
  }

  // Si ya existía, intentamos loguearlo para obtener su ID
  const { data: signInData, error: signInError } = await supabase.auth.signInWithPassword({
    email: 'admin@jitsite.com',
    password: 'password123',
  });
  
  const adminId = signInData?.user?.id || authData?.user?.id;
  if (!adminId) {
    console.error("No se pudo obtener el ID del admin");
    return;
  }
  console.log("Admin ID:", adminId);

  // 2. Crear un Driver
  const { data: driverAuth, error: driverAuthErr } = await supabase.auth.admin.createUser({
    email: 'driver@jitsite.com',
    password: 'password123',
    email_confirm: true,
  });
  const driverId = driverAuth?.user?.id;
  console.log("Driver ID:", driverId);

  // 3. Crear Flota
  const { data: fleet, error: fleetError } = await supabase.from('fleets').insert([
    { id: '48432f69-952e-4536-bd5a-095a3d2bb8cf', name: 'Test Fleet', status: 'active' }
  ]).select().single();
  
  if (fleetError && fleetError.code !== '23505') console.error("Fleet error:", fleetError);

  // Update perfiles para asegurar que pertenezcan a la flota y tengan roles
  await supabase.from('profiles').update({ fleet_id: '48432f69-952e-4536-bd5a-095a3d2bb8cf', role: 'supervisor' }).eq('id', adminId);
  await supabase.from('profiles').update({ fleet_id: '48432f69-952e-4536-bd5a-095a3d2bb8cf', role: 'operator' }).eq('id', driverId);

  // 4. Crear Categoría de Licencia
  const { data: licenseCat, error: lcError } = await supabase.from('license_categories').insert([
    { code: 'HR', description: 'Heavy Rigid' }
  ]).select().single();
  
  const licenseCatId = licenseCat?.id;

  const { data: licenseCat2, error: lc2Error } = await supabase.from('license_categories').insert([
    { code: 'LV', description: 'Light Vehicle' }
  ]).select().single();
  
  // 5. Crear Activos
  const { data: asset, error: assetErr } = await supabase.from('assets').insert([
    { 
      fleet_id: '48432f69-952e-4536-bd5a-095a3d2bb8cf', 
      internal_code: 'DT-001', 
      category: 'heavy_machinery', 
      status: 'operational', 
      current_engine_hours: 100, 
      required_license_id: licenseCatId
    }
  ]).select().single();
  const assetId = asset?.id;
  
  const { data: assetNoLic } = await supabase.from('assets').insert([
    { 
      fleet_id: '48432f69-952e-4536-bd5a-095a3d2bb8cf', 
      internal_code: 'DT-002', 
      category: 'heavy_machinery', 
      status: 'operational', 
      current_engine_hours: 100, 
      required_license_id: licenseCat2?.id
    }
  ]).select().single();
  const assetNoLicId = assetNoLic?.id;

  // 6. Asignar Licencia al Driver
  await supabase.from('driver_licenses').insert([
    {
      driver_id: driverId,
      license_category_id: licenseCatId,
      issued_date: '2020-01-01',
      expiry_date: '2030-01-01'
    }
  ]);

  // 7. Insertar Turno de Fatiga (> 12h)
  const shiftStart = new Date();
  shiftStart.setHours(shiftStart.getHours() - 14);
  const shiftEnd = new Date();
  shiftEnd.setHours(shiftEnd.getHours() - 1);
  
  await supabase.from('asset_assignments').insert([
    {
      fleet_id: '48432f69-952e-4536-bd5a-095a3d2bb8cf',
      asset_id: assetId,
      driver_id: driverId,
      assigned_by: adminId,
      shift_start: shiftStart.toISOString(),
      shift_end: shiftEnd.toISOString()
    }
  ]);

  console.log("--- SEED COMPLETADO ---");
  console.log(`MOCK_FLEET_ID: 48432f69-952e-4536-bd5a-095a3d2bb8cf`);
  console.log(`MOCK_ASSET_ID: ${assetId}`);
  console.log(`MOCK_ASSET_NO_LIC_ID: ${assetNoLicId}`);
  console.log(`MOCK_DRIVER_ID: ${driverId}`);
}

prepare();
