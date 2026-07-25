import { createClient } from '@supabase/supabase-js';

// Usamos el Service Role Key por defecto de Supabase CLI local para poder invocar admin.createUser
const SUPABASE_URL = process.env.VITE_SUPABASE_URL || 'http://127.0.0.1:54321';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false }
});

async function seedUsers() {
  console.log('🌱 Iniciando inyección segura de identidades (GoTrue)...');

  const usersToCreate = [
    { email: 'admin@jitsite.com', password: 'password123', role: 'super_admin' },
    { email: 'fleet@jitsite.com', password: 'password123', role: 'fleet_manager' },
    { email: 'supervisor@jitsite.com', password: 'password123', role: 'supervisor' },
    { email: 'operator@jitsite.com', password: 'password123', role: 'operator' },
    { email: 'fitter@jitsite.com', password: 'password123', role: 'heavy_mechanic' },
    { email: 'tollgate@jitsite.com', password: 'password123', role: 'weighbridge' }
  ];

  for (const user of usersToCreate) {
    const { data, error } = await supabase.auth.admin.createUser({
      email: user.email,
      password: user.password,
      email_confirm: true,
      user_metadata: { role: user.role }
    });

    if (error) {
      console.error(`❌ Error creando ${user.email}:`, error.message || error);
    } else {
      // El trigger secure_auth_trigger fuerza a 'driver' a todos los nuevos registros por seguridad.
      // Como este script se ejecuta con Service Role (máximo privilegio), podemos hacer un UPDATE 
      // manual en la tabla profiles para sobreescribir el trigger de seguridad y asignar el rol real.
      const { error: profileError } = await supabase
        .from('profiles')
        .update({ role: user.role })
        .eq('id', data.user.id);
        
      if (profileError) {
         console.error(`⚠️ Identidad creada, pero falló la elevación de privilegios en profiles:`, profileError);
      } else {
         console.log(`✅ Usuario creado y elevado a ${user.role}: ${user.email} (ID: ${data.user.id})`);
      }
    }
  }

  console.log('✅ Identidades creadas con éxito a través del motor GoTrue.');
  console.log('👉 Siguiente paso: Ejecuta seed.sql para poblar la topología operativa.');
}

seedUsers().catch(console.error);
