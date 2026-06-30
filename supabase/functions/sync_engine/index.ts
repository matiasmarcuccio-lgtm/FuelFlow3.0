import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  // Configuración de CORS para permitir peticiones desde la app móvil
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const url = new URL(req.url)
    const action = url.searchParams.get('action')

    // 1. Validar JWT e inicializar el cliente como el usuario autenticado
    // Esto es crucial: garantiza que el RLS funcione en la base de datos
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: { headers: { Authorization: req.headers.get('Authorization')! } },
      }
    )

    // Validar que el token pertenezca a un usuario real
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser()
    if (authError || !user) {
      throw new Error('No autorizado: Token JWT inválido o ausente')
    }

    // 2. Enrutar según el protocolo de WatermelonDB (Pull vs Push)
    if (action === 'push') {
      const { changes } = await req.json()

      // Delegar la transacción masiva al motor de PostgreSQL (PL/pgSQL)
      const { error: rpcError } = await supabaseClient.rpc('sync_watermelondb_push', { changes })

      if (rpcError) {
        console.error("Error en la sincronización push (Rollback ejecutado):", rpcError)
        throw new Error(`Fallo en el motor transaccional: ${rpcError.message}`)
      }

      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    } 
    
    else if (action === 'pull') {
      const lastPulledAt = url.searchParams.get('last_pulled_at')
      
      // TODO: Implementar la extracción de deltas (sync_watermelondb_pull)
      // Para efectos de esta prueba, retornamos un objeto vacío
      const changes = {
        fatigue_logs: { created: [], updated: [], deleted: [] },
        nhvr_compliance_logs: { created: [], updated: [], deleted: [] },
        expenses: { created: [], updated: [], deleted: [] },
      }

      return new Response(JSON.stringify({ changes, timestamp: Date.now() }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    } 
    
    else {
      throw new Error('Acción no válida. Use ?action=pull o ?action=push')
    }

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})
