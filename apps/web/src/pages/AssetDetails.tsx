import { useParams, useNavigate } from 'react-router-dom';
import { useAssetById } from '../hooks/useAssetById';
import { useUpdateAsset } from '../hooks/useUpdateAsset';
import { AssetForm } from '../components/AssetForm';
import type { AssetFormData } from '../schemas/assetSchema';
import { mapAssetRowToInput } from '../utils/assetMappers';
import { useToast } from '@/hooks/use-toast';
import { Button } from '@/components/ui/button';
import { ArrowLeft } from 'lucide-react';

export default function AssetDetails() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { toast } = useToast();
  
  const { data: asset, isLoading, error } = useAssetById(id);
  const { mutateAsync: updateAsset, isPending } = useUpdateAsset();

  const handleUpdate = async (formData: AssetFormData): Promise<AssetFormData> => {
    try {
      if (!id) throw new Error("ID perdido");
      
      const updatedRow = await updateAsset({ id, ...formData });
      
      // Poda de Variables de Sistema estricta
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
      const { id: _, created_at: __, fleet_id: ___, ...cleanFormData } = updatedRow as import('@fuelflow/shared-types').AssetRow;
      
      toast({
        title: "Activo Actualizado",
        description: "Los metadatos técnicos han sido guardados correctamente.",
        variant: "default", // green success normally, shadcn uses default
      });
      
      // Retornar el objeto podado geométricamente válido para Zod
      return cleanFormData as AssetFormData;
    } catch (err: any) {
      toast({
        title: "Error de Guardado",
        description: err.message,
        variant: "destructive",
      });
      throw err;
    }
  };

  if (isLoading) {
    return (
      <div className="min-h-screen bg-gray-50/50 p-4 md:p-8">
        <div className="max-w-4xl mx-auto space-y-8 animate-pulse">
           <div className="h-10 bg-gray-200 rounded w-1/3"></div>
           <div className="h-96 bg-gray-200 rounded-xl"></div>
        </div>
      </div>
    );
  }

  if (error || !asset) {
    return (
      <div className="min-h-screen bg-gray-50/50 p-4 md:p-8">
        <div className="max-w-4xl mx-auto text-center space-y-4">
          <h1 className="text-2xl font-bold text-gray-900">Activo no encontrado</h1>
          <p className="text-gray-500">No se pudo cargar el perfil del vehículo.</p>
          <Button onClick={() => navigate('/')}>Volver al Panel</Button>
        </div>
      </div>
    );
  }

  // Preparamos el AssetRow puro como AssetFormInput
  const initialFormData = mapAssetRowToInput(asset);

  return (
    <div className="min-h-screen bg-gray-50/50 p-4 md:p-8">
      <div className="max-w-4xl mx-auto space-y-8">
        
        <header className="flex flex-col md:flex-row md:items-center justify-between bg-white p-6 rounded-xl shadow-sm border gap-4">
          <div className="flex items-center gap-4">
            <Button variant="ghost" size="icon" onClick={() => navigate('/')}>
              <ArrowLeft className="w-5 h-5" />
            </Button>
            <div>
              <h1 className="text-2xl font-bold tracking-tight text-gray-900">
                Editar Vehículo: {asset.vehicle_metadata?.nickname || asset.id.substring(0, 8)}
              </h1>
              <p className="text-sm text-gray-500 mt-1">VIN: {asset.vehicle_metadata?.vin || 'N/A'}</p>
            </div>
          </div>
        </header>

        <main className="bg-white p-6 md:p-8 rounded-xl shadow-sm border">
          <AssetForm 
            key={asset.id} 
            initialData={initialFormData} 
            onSubmit={handleUpdate} 
            isPending={isPending} 
          />
        </main>
      </div>
    </div>
  );
}
