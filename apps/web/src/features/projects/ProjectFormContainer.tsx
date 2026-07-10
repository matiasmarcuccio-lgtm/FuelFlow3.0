import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase';
import { ProjectFormPresenter } from './ProjectFormPresenter';
import { ProjectSchema, type Project } from '../../schemas/core';
import { useState } from 'react';

interface Props {
  projectId?: string;
  onSuccess?: () => void;
}

export function ProjectFormContainer({ projectId, onSuccess }: Props) {
  const queryClient = useQueryClient();
  const [submitError, setSubmitError] = useState<string | null>(null);

  const { data: project, isPending: isFetching, isError: isFetchError, error: fetchError } = useQuery({
    queryKey: ['project', projectId],
    queryFn: async () => {
      if (!projectId) return null;
      const { data, error } = await supabase
        .from('projects')
        .select('*')
        .eq('id', projectId)
        .single();
      
      if (error) throw error;
      return ProjectSchema.parse(data);
    },
    enabled: !!projectId,
    retry: false,
  });

  const mutation = useMutation({
    mutationFn: async (values: Partial<Project>) => {
      const { data, error } = await supabase
        .from('projects')
        .upsert({ ...values, ...(projectId ? { id: projectId } : {}) })
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['business_metrics'] });
      queryClient.invalidateQueries({ queryKey: ['projects'] });
      setSubmitError(null);
      onSuccess?.();
    },
    onError: (err: Error) => {
      setSubmitError(err.message || 'Error saving project. RLS policy violation?');
    }
  });

  if (projectId && isFetching) return <div className="p-4 text-gray-500">Loading project data...</div>;
  if (isFetchError) return <div className="p-4 text-red-500">Error loading project: {fetchError?.message}</div>;

  return (
    // REGLA: Escrutinio del Ciclo de Vida (Reciclaje del DOM)
    // El atributo key fuerza a React a desmontar y volver a montar el componente
    // cuando cambia el ID, evitando que el estado asíncrono colisione.
    <ProjectFormPresenter 
      key={projectId || 'new-project'} 
      initialData={project} 
      onSubmit={(data) => mutation.mutate(data)}
      isPending={mutation.isPending}
      submitError={submitError}
    />
  );
}
