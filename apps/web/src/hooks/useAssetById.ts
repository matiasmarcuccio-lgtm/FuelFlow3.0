import { useQuery } from '@tanstack/react-query';
import { supabase } from '../lib/supabase';
import type { AssetRow } from '@fuelflow/shared-types';

export const useAssetById = (id: string | undefined) => {
  return useQuery({
    queryKey: ['asset', id],
    queryFn: async (): Promise<AssetRow> => {
      if (!id) throw new Error("ID de activo no proporcionado");
      const { data, error } = await supabase
        .from('assets')
        .select('*')
        .eq('id', id)
        .single();

      if (error) throw new Error(error.message);
      return data as AssetRow;
    },
    enabled: !!id,
  });
};
