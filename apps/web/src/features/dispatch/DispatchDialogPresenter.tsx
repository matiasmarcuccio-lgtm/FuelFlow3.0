import { useState, useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import * as z from 'zod';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from '@/components/ui/dialog';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Input } from '@/components/ui/input';

// SSOT: Tipos de la base de datos (usando types generados o los inferidos de Supabase)
import type { Database } from '@fuelflow/shared-types';
type Asset = Database['public']['Tables']['assets']['Row'];
type Profile = Database['public']['Tables']['profiles']['Row'];

const dispatchSchema = z.object({
  driverId: z.string().uuid({ message: 'Must select a valid driver' }),
  fatigueOverride: z.string().optional(),
});

type DispatchFormValues = z.infer<typeof dispatchSchema>;

interface DispatchDialogPresenterProps {
  asset: Asset | null;
  drivers: Profile[];
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (data: { assetId: string; driverId: string; fatigueOverride?: string }) => Promise<void>;
  isPending: boolean;
  error: { code: string; message: string } | null;
}

export const DispatchDialogPresenter = ({
  asset,
  drivers,
  isOpen,
  onClose,
  onSubmit,
  isPending,
  error,
}: DispatchDialogPresenterProps) => {
  const [requiresOverride, setRequiresOverride] = useState(false);

  const {
    register,
    handleSubmit,
    setValue,
    reset,
    formState: { errors },
  } = useForm<DispatchFormValues>({
    resolver: zodResolver(dispatchSchema),
    defaultValues: { fatigueOverride: '' },
  });

  // El Escrutinio del Ciclo de Vida: Purgar estados fantasmas al cerrar/abrir
  useEffect(() => {
    if (!isOpen) {
      reset();
      setRequiresOverride(false);
    }
  }, [isOpen, reset]);

  // Si el backend escupe P0001 WHS_FATIGUE_LIMIT, abrimos el campo de override
  useEffect(() => {
    if (error?.code === 'P0001' && error.message.includes('WHS_FATIGUE_LIMIT')) {
      setRequiresOverride(true);
    }
  }, [error]);

  const handleFormSubmit = async (data: DispatchFormValues) => {
    if (!asset) return;
    await onSubmit({
      assetId: asset.id,
      driverId: data.driverId,
      fatigueOverride: data.fatigueOverride || undefined,
    });
  };

  if (!asset) return null;

  // Render condicional de errores duros que no tienen escape
  const isHardError = error?.code === '23P01' || (error?.code === 'P0001' && error.message.includes('WHS_INVALID_LICENSE'));

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !isPending && !open && onClose()}>
      <DialogContent className="sm:max-w-[425px] bg-slate-950 text-slate-50 border-slate-800">
        <DialogHeader>
          <DialogTitle className="text-xl">Dispatch Assignment</DialogTitle>
          <DialogDescription className="text-slate-400">
            Assigning asset <span className="font-mono text-white">{asset.internal_code}</span> to an operator.
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit(handleFormSubmit)} className="space-y-6 pt-4">
          <div className="space-y-2">
            <Label htmlFor="driverId">Select Operator</Label>
            <Select disabled={isPending} onValueChange={(val) => setValue('driverId', val)}>
              <SelectTrigger id="driverId" className="bg-slate-900 border-slate-700">
                <SelectValue placeholder="Choose operator..." />
              </SelectTrigger>
              <SelectContent className="bg-slate-900 border-slate-700 text-slate-100">
                {drivers.map((d) => (
                  <SelectItem key={d.id} value={d.id}>
                    {d.full_name || d.id.substring(0,8)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {errors.driverId && <p className="text-red-500 text-sm">{errors.driverId.message}</p>}
          </div>

          {requiresOverride && (
            <div className="space-y-2 p-3 bg-red-950/30 border border-red-900 rounded-md">
              <Label htmlFor="fatigueOverride" className="text-red-400 font-semibold flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse"></span>
                Fatigue Limit Exceeded
              </Label>
              <p className="text-xs text-slate-400 pb-2">
                Operator has exceeded 12h WHS limit. A legal override is required.
              </p>
              <Input 
                id="fatigueOverride" 
                {...register('fatigueOverride')} 
                placeholder="Reason for overriding fatigue limit..." 
                className="bg-slate-900 border-red-800 focus-visible:ring-red-500"
                disabled={isPending}
                required
              />
            </div>
          )}

          {isHardError && (
            <div className="p-3 bg-red-950 border border-red-800 rounded-md">
              <p className="text-sm text-red-200 font-medium">
                {error.code === '23P01' 
                  ? 'Temporal Collision: Asset or Operator already has an active shift.'
                  : 'WHS Violation: Operator lacks required license.'}
              </p>
            </div>
          )}

          <DialogFooter>
            <Button 
              type="button" 
              variant="outline" 
              onClick={onClose} 
              disabled={isPending}
              className="border-slate-700 hover:bg-slate-800"
            >
              Cancel
            </Button>
            <Button 
              type="submit" 
              disabled={isPending}
              className="bg-emerald-600 hover:bg-emerald-700 text-white"
            >
              {isPending ? 'Assigning...' : requiresOverride ? 'Force Assign (Audit)' : 'Assign Shift'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};
