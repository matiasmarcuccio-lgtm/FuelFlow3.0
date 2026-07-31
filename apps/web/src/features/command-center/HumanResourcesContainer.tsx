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
        p_fleet_id: fleetId,
        p_role: role
      });
      if (error) throw error;
      
      // El RPC ya inserta en fleet_invites. 
      // Retorna el token generado.
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['invites', fleetId] });
    }
  });

  // 4. Mutación para dar de baja a un usuario (Soft Delete)
  const disableCrewMemberMutation = useMutation({
    mutationFn: async (profileId: string) => {
      const { error } = await supabase.rpc('fn_disable_crew_member', {
        p_profile_id: profileId
      });
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['crew', fleetId] });
    }
  });

  // 5. Mutación para revocar un token pendiente
  const revokeInviteMutation = useMutation({
    mutationFn: async (token: string) => {
      const { error } = await supabase.rpc('fn_revoke_fleet_invite', {
        p_token: token
      });
      if (error) throw error;
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
      onDisableMember={(id) => disableCrewMemberMutation.mutate(id)}
      onRevokeInvite={(token) => revokeInviteMutation.mutate(token)}
    />
  );
};
