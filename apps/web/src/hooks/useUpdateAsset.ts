import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../lib/supabase';
import type { AssetInsert, AssetRow } from '@fuelflow/shared-types';

export type UpdateAssetPayload = Partial<Omit<AssetInsert, 'id' | 'created_at' | 'fleet_id'>> & { id: string };

export const useUpdateAsset = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (payload: UpdateAssetPayload): Promise<AssetRow> => {
      const { id, ...updateData } = payload;
      
      const { data, error } = await supabase
        .from('assets')
        .update(updateData as any)
        .eq('id', id as string)
        .select()
        .single();

      if (error) {
        console.error('Error updating asset:', error);
        throw new Error(error.message);
      }

      return data as AssetRow;
    },
    onSuccess: (data) => {
      // Invalidate general list and specific item
      queryClient.invalidateQueries({ queryKey: ['assets'] });
      queryClient.invalidateQueries({ queryKey: ['asset', data.id] });
    },
  });
};
