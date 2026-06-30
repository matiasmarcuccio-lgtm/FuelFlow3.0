import { createClient } from '@supabase/supabase-js';

// En producción, estas variables se inyectan a través del bundler de Expo (.env)
const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL || 'https://mmhnagtwcpynkvcovlsm.supabase.co';
const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY || 'public-anon-key-mock';

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
