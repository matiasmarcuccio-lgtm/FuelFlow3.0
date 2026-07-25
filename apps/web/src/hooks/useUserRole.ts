import { useQuery } from '@tanstack/react-query';
import { supabase } from '../lib/supabase';

export interface UserProjectRole {
    project_id: string;
    role: 'supervisor' | 'weighbridge' | 'fitter' | 'operator';
    projects: {
        name: string;
    };
}

export const useUserRoles = () => {
    return useQuery({
        queryKey: ['user_roles'],
        queryFn: async () => {
            const { data: userData, error: authError } = await supabase.auth.getUser();
            if (authError || !userData?.user) throw new Error('Not authenticated');

            // 1. Verificar Rol Global
            const { data: profile } = await supabase
                .from('profiles')
                .select('role, fleet_id')
                .eq('id', userData.user.id)
                .single();

            // 2. Si es super_admin o fleet_manager, inyectar jurisdicción global/flota
            if (profile && (profile.role === 'super_admin' || profile.role === 'fleet_manager')) {
                let query = supabase.from('projects').select('id, name');
                
                // Si es gestor de flota, limitamos a los proyectos donde opera su flota
                // (Por simplicidad de la arquitectura actual, asumimos que fleet_manager 
                // puede ver todos los proyectos o filtramos por lógica de negocio pertinente. 
                // Aquí listaremos todos los proyectos disponibles para selección táctica).
                
                const { data: allProjects, error: pError } = await query;
                if (pError) throw pError;

                // Si la base de datos está completamente virgen (0 proyectos),
                // inyectamos un nodo sintético "Headquarters" para que el super_admin
                // pueda entrar al Builder y construir la topología.
                if (!allProjects || allProjects.length === 0) {
                    return [{
                        project_id: 'hq-bootstrap-0000',
                        role: profile.role as 'super_admin' | 'fleet_manager',
                        projects: { name: 'Headquarters (System Bootstrap)' }
                    }] as unknown as UserProjectRole[];
                }

                return allProjects.map(p => ({
                    project_id: p.id,
                    role: profile.role as 'super_admin' | 'fleet_manager',
                    projects: { name: p.name }
                })) as unknown as UserProjectRole[];
            }

            // 3. Flujo estándar para roles confinados (supervisores, mecánicos)
            const { data, error } = await supabase
                .from('project_members')
                .select(`
                    project_id,
                    role,
                    projects ( name )
                `)
                .eq('user_id', userData.user.id);
                
            if (error) throw error;
            return data as UserProjectRole[];
        },
        staleTime: 5 * 60 * 1000, // 5 minutes
    });
};
