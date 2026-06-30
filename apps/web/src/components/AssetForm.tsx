import { useForm, useWatch } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useEffect } from 'react';

import { ASSET_TYPES, TRAILER_TYPES } from '@fuelflow/shared-types';
import { assetSchema } from '../schemas/assetSchema';
import type { AssetFormData, AssetFormInput } from '../schemas/assetSchema';

import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from '@/components/ui/form';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

interface AssetFormProps {
  initialData?: AssetFormInput;
  onSubmit: (data: AssetFormData) => Promise<AssetFormData>;
  isPending: boolean;
}

export function AssetForm({ initialData, onSubmit, isPending }: AssetFormProps) {
  const form = useForm<AssetFormInput, any, AssetFormData>({
    resolver: zodResolver(assetSchema),
    defaultValues: initialData || {
      asset_type: 'Heavy Rigid (HR)',
      trailer_type: null,
      max_payload_kg: null,
      pallet_capacity: null,
      is_nhvr_accredited: false,
      vehicle_metadata: {
        vin: '',
        year: new Date().getFullYear(),
        make_model: '',
        nickname: '',
      },
      compliance_records: {
        insurance_provider: '',
        policy_expiry: '',
        service_history_url: '',
      },
    },
  });

  // Limpieza Activa de Memoria
  const assetType = useWatch({ control: form.control, name: 'asset_type' });

  useEffect(() => {
    if (assetType !== 'Standalone Trailer') {
      form.setValue('trailer_type', null);
    }
  }, [assetType, form.setValue]);

  const handleSubmit = async (data: AssetFormData) => {
    try {
      const newData = await onSubmit(data);
      // Actualizamos el estado con los datos asimilados por el servidor
      form.reset(newData);
    } catch (error) {
      // El contenedor maneja los errores visuales (Toast), aquí solo atrapamos
      console.error("Form error:", error);
    }
  };

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(handleSubmit)} className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
          {/* Mechanical Specs Block */}
          <div className="space-y-6">
            <h3 className="text-lg font-medium border-b pb-2">Technical Specifications</h3>
            
            <FormField
              control={form.control}
              name="asset_type"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Asset Type</FormLabel>
                  <Select onValueChange={field.onChange} defaultValue={field.value}>
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="Select vehicle type" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {ASSET_TYPES.map(type => (
                        <SelectItem key={type} value={type}>{type}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )}
            />

            {assetType === 'Standalone Trailer' && (
              <FormField
                control={form.control}
                name="trailer_type"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Trailer Classification</FormLabel>
                    <Select onValueChange={field.onChange} value={field.value || undefined}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue placeholder="Select trailer type" />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {TRAILER_TYPES.map(type => (
                          <SelectItem key={type} value={type}>{type}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />
            )}

            <FormField
              control={form.control}
              name="max_payload_kg"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Max Payload (kg)</FormLabel>
                  <FormControl>
                    <Input type="number" placeholder="25000" {...field} value={field.value ?? ''} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="pallet_capacity"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Pallet Capacity</FormLabel>
                  <FormControl>
                    <Input type="number" placeholder="34" {...field} value={field.value ?? ''} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
          </div>

          {/* NHVR & Metadata Block */}
          <div className="space-y-6">
            <h3 className="text-lg font-medium border-b pb-2">NHVR & Legal Metadata</h3>
            
            <FormField
              control={form.control}
              name="is_nhvr_accredited"
              render={({ field }) => (
                <FormItem className="flex flex-row items-start space-x-3 space-y-0 rounded-md border p-4">
                  <FormControl>
                    <Checkbox
                      checked={!!field.value}
                      onCheckedChange={field.onChange}
                    />
                  </FormControl>
                  <div className="space-y-1 leading-none">
                    <FormLabel>
                      NHVR Accredited
                    </FormLabel>
                    <p className="text-sm text-muted-foreground">
                      This vehicle is enrolled in the National Heavy Vehicle Regulator scheme.
                    </p>
                  </div>
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="vehicle_metadata.nickname"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Fleet Nickname</FormLabel>
                  <FormControl>
                    <Input placeholder="e.g. TRK-001" {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <div className="grid grid-cols-2 gap-4">
              <FormField
                control={form.control}
                name="vehicle_metadata.make_model"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Make & Model</FormLabel>
                    <FormControl>
                      <Input placeholder="Kenworth K200" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="vehicle_metadata.year"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Year</FormLabel>
                    <FormControl>
                      <Input type="number" {...field} value={field.value ?? ''} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>

            <FormField
              control={form.control}
              name="vehicle_metadata.vin"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>VIN (Vehicle Identification Number)</FormLabel>
                  <FormControl>
                    <Input placeholder="17-character VIN" {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <div className="grid grid-cols-2 gap-4">
              <FormField
                control={form.control}
                name="compliance_records.insurance_provider"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Insurance Provider</FormLabel>
                    <FormControl>
                      <Input placeholder="NTI" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="compliance_records.policy_expiry"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Policy Expiry</FormLabel>
                    <FormControl>
                      <Input type="date" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>

          </div>
        </div>

        <div className="flex justify-end border-t pt-4">
          <Button type="submit" disabled={isPending} className="w-full md:w-auto">
            {isPending ? 'Procesando...' : 'Guardar Información'}
          </Button>
        </div>
      </form>
    </Form>
  );
}
