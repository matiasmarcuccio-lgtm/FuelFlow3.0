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
