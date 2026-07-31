import React from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';
import { CrewManagementPresenter } from './CrewManagementPresenter';

interface HumanResourcesContainerProps {
  fleetId: string;
}

export const HumanResourcesContainer: React.FC<HumanResourcesContainerProps> = ({ fleetId }) => {
  const queryClient = useQueryClient();

  // 1. Cargar Personal Activo
  const { data: crew = [], isLoading: isLoadingCrew } = useQuery({
    queryKey: ['crew', fleetId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('id, full_name, role, status, updated_at')
        .eq('fleet_id', fleetId)
        .order('role', { ascending: true });
        
      if (error) throw error;
      return data;
    }
  });

  // 2. Cargar Invitaciones Pendientes
  const { data: invites = [], isLoading: isLoadingInvites } = useQuery({
    queryKey: ['invites', fleetId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('fleet_invites')
        .select('id, token, role, expires_at, consumed_at')
        .eq('fleet_id', fleetId)
        .order('created_at', { ascending: false });
        
      if (error) throw error;
      return data;
    }
  });

  // 3. Mutación para Generar Nuevo Token (URL Onboarding)
  const generateInviteMutation = useMutation({
    mutationFn: async (role: string) => {
      const { data, error } = await supabase.rpc('fn_generate_fleet_invite', {
        p_fleet_id: fleetId
      });
      if (error) throw error;
      
      // Actualizamos el rol del token generado
      const { error: updateError } = await supabase
        .from('fleet_invites')
        .update({ role })
        .eq('token', data);
        
      if (updateError) throw updateError;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['invites', fleetId] });
    }
  });

  if (isLoadingCrew || isLoadingInvites) {
    return <div className="text-white p-6 font-mono text-xl">SINCRONIZANDO RECURSOS HUMANOS...</div>;
  }

  return (
    <CrewManagementPresenter 
      crew={crew}
      invites={invites}
      isGenerating={generateInviteMutation.isPending}
      onGenerateInvite={(role) => generateInviteMutation.mutate(role)}
    />
  );
};
