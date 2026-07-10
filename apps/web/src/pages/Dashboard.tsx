import { useQuery } from '@tanstack/react-query';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { useCurrentProfile } from '../hooks/useCurrentProfile';
import { useCreateAsset } from '../hooks/useCreateAsset';
import { AssetForm } from '../components/AssetForm';
import type { AssetFormData } from '../schemas/assetSchema';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import { Link, useNavigate } from 'react-router-dom';

export default function Dashboard() {
  const { session } = useAuth();
  const { toast } = useToast();
  const navigate = useNavigate();
  
  // 1. Cargamos el perfil maestro (Capa de Identity)
  const { data: profile, isLoading: loadingProfile, error: errorProfile } = useCurrentProfile();

  // 2. Cargamos los camiones
  const { data: assets, isLoading: loadingAssets, error: errorAssets } = useQuery({
    queryKey: ['assets', profile?.fleet_id],
    queryFn: async () => {
      const { data, error } = await supabase.from('assets').select('*').order('created_at', { ascending: false });
      if (error) throw new Error(error.message);
      return data;
    },
    enabled: !!session && !!profile?.fleet_id,
  });

  const { mutateAsync: createAsset, isPending: creatingAsset } = useCreateAsset();

  const handleCreate = async (formData: AssetFormData): Promise<AssetFormData> => {
    try {
      const newRow = await createAsset(formData);
      
      // Poda Absoluta
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
      const { id: _, created_at: __, fleet_id: ___, ...cleanFormData } = newRow as import('@fuelflow/shared-types').AssetRow;
      
      toast({
        title: "Vehicle Registrado",
        description: "El activo ha sido ingresado a la flota.",
      });

      // Purgado Absoluto: Redireccionamos a la vista de edición para evitar duplicados
      navigate(`/assets/${newRow.id}`);
      
      return cleanFormData as AssetFormData;
    } catch (err: any) {
      toast({
        title: "Error de Registro",
        description: err.message,
        variant: "destructive",
      });
      throw err;
    }
  };

  const handleLogout = async () => {
    await supabase.auth.signOut();
  };

  return (
    <div className="min-h-screen bg-gray-50/50 p-4 md:p-8">
      <div className="max-w-7xl mx-auto space-y-8">
        
        <header className="flex justify-between items-center bg-white p-6 rounded-xl shadow-sm border">
          <div>
            <h1 className="text-3xl font-bold tracking-tight text-gray-900">Panel de Control Logístico</h1>
            {profile && (
              <p className="text-sm text-gray-500 mt-1">
                Fleet: <strong className="text-gray-900">{profile.full_name}</strong> | Rol: {profile.role}
              </p>
            )}
          </div>
          <Button variant="outline" onClick={handleLogout}>Logout</Button>
        </header>

        <main className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          
          {/* Main Form Area */}
          <div className="lg:col-span-2 bg-white p-6 md:p-8 rounded-xl shadow-sm border">
            <h2 className="text-2xl font-semibold mb-6">Register New Asset</h2>
            {loadingProfile ? (
              <p className="text-sm text-muted-foreground animate-pulse">Descargando identidad de flota...</p>
            ) : errorProfile ? (
              <p className="text-sm text-destructive">Error cargando perfil: {errorProfile.message}</p>
            ) : profile ? (
              <AssetForm onSubmit={handleCreate} isPending={creatingAsset} />
            ) : null}
          </div>

          {/* Sidebar / Assets List */}
          <div className="bg-white p-6 rounded-xl shadow-sm border h-fit">
            <h2 className="text-xl font-semibold mb-4">Active Fleet</h2>
            
            {loadingAssets && <p className="text-sm text-muted-foreground animate-pulse">Cargando flota...</p>}
            {errorAssets && <p className="text-sm text-destructive">Error: {errorAssets.message}</p>}
            
            {assets && assets.length === 0 && (
              <div className="text-center p-6 border-2 border-dashed rounded-lg bg-gray-50">
                <p className="text-sm text-gray-500">No assets registered yet.</p>
              </div>
            )}

            {assets && assets.length > 0 && (
              <ul className="space-y-3">
                {assets.map(asset => (
                  <li key={asset.id}>
                    <Link 
                      to={`/assets/${asset.id}`}
                      className="p-3 bg-gray-50 rounded-lg border flex flex-col hover:bg-gray-100 transition-colors"
                    >
                      <span className="font-medium text-slate-900">
                      {((asset.vehicle_metadata as unknown) as import('@fuelflow/shared-types').VehicleMetadata)?.nickname || asset.id.split('-')[0]}
                    </span>
                      <span className="text-xs text-gray-500">{asset.asset_type}</span>
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </div>

        </main>
      </div>
    </div>
  );
}
