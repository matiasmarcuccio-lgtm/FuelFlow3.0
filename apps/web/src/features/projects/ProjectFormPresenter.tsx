import { useForm, useWatch } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { ProjectSchema, type Project } from '../../schemas/core';
import { useEffect } from 'react';
import { Loader2, AlertCircle } from 'lucide-react';
import { z } from 'zod';

// We omit ID and created_at for the form inputs
const ProjectFormSchema = ProjectSchema.omit({ id: true, created_at: true }).extend({
    name: z.string().min(1, 'Project name is required'),
    status: z.string(),
});
type ProjectFormData = z.infer<typeof ProjectFormSchema>;

interface Props {
  initialData?: Project | null;
  onSubmit: (data: ProjectFormData) => void;
  isPending: boolean;
  submitError: string | null;
}

export function ProjectFormPresenter({ initialData, onSubmit, isPending, submitError }: Props) {
  const { register, handleSubmit, control, setValue, formState: { errors } } = useForm<ProjectFormData>({
    resolver: zodResolver(ProjectFormSchema),
    defaultValues: {
      name: initialData?.name || '',
      client_name: initialData?.client_name || '',
      project_type: initialData?.project_type || 'short_term',
      start_date: initialData?.start_date || '',
      estimated_end_date: initialData?.estimated_end_date || '',
      status: initialData?.status || 'planning',
    }
  });

  // REGLA: Prevención de Estado Fantasma
  // Monitor the project type. If it changes to 'short_term', clear the estimated_end_date 
  // because short term projects might not need long term estimation, preventing orphan data.
  const projectType = useWatch({ control, name: 'project_type' });
  
  useEffect(() => {
    if (projectType === 'short_term') {
      setValue('estimated_end_date', '');
    }
  }, [projectType, setValue]);

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-6 bg-white p-6 rounded-xl shadow-sm border border-gray-100">
      
      {submitError && (
        <div className="bg-red-50 border-l-4 border-red-500 p-4 rounded-md shadow-sm flex items-center space-x-3">
          <AlertCircle className="h-5 w-5 text-red-500" />
          <p className="text-red-700 font-medium">{submitError}</p>
        </div>
      )}

      <div>
        <label className="block text-sm font-medium text-gray-700">Project Name</label>
        <input 
          {...register('name')}
          disabled={isPending}
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm p-2 border" 
          placeholder="Enter project name..."
        />
        {errors.name && <span className="text-red-500 text-xs mt-1">{errors.name.message}</span>}
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700">Client Name</label>
        <input 
          {...register('client_name')}
          disabled={isPending}
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm p-2 border" 
        />
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-gray-700">Project Type</label>
          <select 
            {...register('project_type')}
            disabled={isPending}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm p-2 border"
          >
            <option value="short_term">Short Term</option>
            <option value="long_term">Long Term</option>
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">Status</label>
          <select 
            {...register('status')}
            disabled={isPending}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm p-2 border"
          >
            <option value="planning">Planning</option>
            <option value="active">Active</option>
            <option value="completed">Completed</option>
          </select>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-gray-700">Start Date</label>
          <input 
            type="date"
            {...register('start_date')}
            disabled={isPending}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm p-2 border" 
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">Estimated End Date</label>
          <input 
            type="date"
            {...register('estimated_end_date')}
            disabled={isPending || projectType === 'short_term'}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm p-2 border disabled:bg-gray-100 disabled:text-gray-400" 
          />
          {projectType === 'short_term' && (
             <p className="text-xs text-gray-500 mt-1">Not required for short term projects.</p>
          )}
        </div>
      </div>

      <div className="flex justify-end pt-4">
        <button
          type="submit"
          disabled={isPending}
          className="inline-flex items-center justify-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-primary text-on-primary hover:bg-primary-container text-on-primary-container focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 transition-colors"
        >
          {isPending ? (
            <>
              <Loader2 className="animate-spin -ml-1 mr-2 h-4 w-4" />
              Saving...
            </>
          ) : (
            'Save Project'
          )}
        </button>
      </div>
    </form>
  );
}
