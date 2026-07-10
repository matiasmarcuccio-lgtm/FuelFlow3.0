import { createClient } from '@supabase/supabase-js';
import jwt from 'jsonwebtoken';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const SUPABASE_URL = process.env.VITE_SUPABASE_URL || 'http://127.0.0.1:54321';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';
const JWT_SECRET = process.env.SUPABASE_JWT_SECRET || 'super-secret-jwt-token-with-at-least-32-characters-long';

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false }
});

async function generateTokens() {
    console.log('Generando JWTs criptográficos estáticos (Bypass de GoTrue)...');
    
    const { data: assignments, error } = await supabase
        .from('shift_assignments')
        .select('driver_id, vehicle_id')
        .eq('status', 'ACTIVE');

    if (error) {
        console.error('Error obteniendo asignaciones de turnos:', error);
        process.exit(1);
    }

    const { data: profiles, error: pError } = await supabase
        .from('profiles')
        .select('id, full_name')
        .like('full_name', 'Driver %');

    if (pError) {
        console.error('Error obteniendo perfiles:', pError);
        process.exit(1);
    }

    console.log(`Se encontraron ${assignments.length} turnos y ${profiles.length} perfiles.`);

    const tokensData = [];

    for (const assignment of assignments) {
        const userId = assignment.driver_id;
        const assetId = assignment.vehicle_id;
        
        const profile = profiles.find(p => p.id === userId);
        if (!profile) continue;

        const fullName = profile.full_name; // e.g. "Driver 1"
        const indexMatch = fullName.match(/Driver (\d+)/);
        
        if (!indexMatch) continue;
        const email = `driver_${indexMatch[1]}@jitsite.com`;

        // Generar JWT a mano para emular a GoTrue
        const payload = {
            aud: "authenticated",
            exp: Math.floor(Date.now() / 1000) + (60 * 60 * 24), // 24 horas
            sub: userId,
            email: email,
            role: "authenticated",
            app_metadata: {
                provider: "email",
                providers: ["email"]
            },
            user_metadata: {
                role: "operator"
            }
        };

        const token = jwt.sign(payload, JWT_SECRET);

        tokensData.push({
            email,
            token,
            asset_id: assetId,
            userId: userId
        });
    }

    const outputPath = path.join(__dirname, 'tokens.json');
    fs.writeFileSync(outputPath, JSON.stringify(tokensData, null, 2));
    
    console.log(`✅ ${tokensData.length} tokens JWT generados e inyectados en scripts/tokens.json`);
}

generateTokens().catch(console.error);
