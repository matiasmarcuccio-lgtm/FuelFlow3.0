import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { BuilderPresenter } from './BuilderPresenter';

export const BuilderDashboard = () => {
  const [progress, setProgress] = useState<any[]>([]);
  const [bottlenecks, setBottlenecks] = useState<any[]>([]);
  const [masterOrders, setMasterOrders] = useState<any[]>([]);
  const [isDeploying, setIsDeploying] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [formData, setFormData] = useState({
    material_type: 'SUB_BASE',
    target_tonnage: 5000,
    requires_4x4: false
  });

  const [isHudActive, setIsHudActive] = useState(false);

  useEffect(() => {
    fetchData();

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === '?' && e.shiftKey) {
        setIsHudActive(prev => !prev);
      }
      if (e.key === 'Escape') {
        setIsHudActive(false);
        setIsDeploying(false);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);

  const fetchData = async () => {
    setIsLoading(true);
    const { data: progressData } = await supabase.from('view_project_progress').select('*');
    if (progressData) setProgress(progressData);

    const { data: bottleneckData } = await supabase.from('view_site_bottlenecks').select('*');
    if (bottleneckData) setBottlenecks(bottleneckData);

    const { data: ordersData } = await supabase.from('master_orders').select('*').order('created_at', { ascending: false });
    if (ordersData) setMasterOrders(ordersData);
    setIsLoading(false);
  };

  const handleDeployPipeline = async () => {
    const { error } = await supabase.from('master_orders').insert({
      material_type: formData.material_type,
      target_tonnage: formData.target_tonnage,
      requires_4x4_traction: formData.requires_4x4,
      origin_geofence: { lat: -42.8821, lng: 147.3272, radius: 50 },
      destination_geofence: { lat: -42.8850, lng: 147.3300, radius: 50 }
    });
    if (!error) {
      setIsDeploying(false);
      fetchData();
    }
  };

  return (
    <BuilderPresenter 
      progress={progress}
      bottlenecks={bottlenecks}
      masterOrders={masterOrders}
      isDeploying={isDeploying}
      setIsDeploying={setIsDeploying}
      formData={formData}
      setFormData={setFormData}
      isHudActive={isHudActive}
      setIsHudActive={setIsHudActive}
      handleDeployPipeline={handleDeployPipeline}
      isLoading={isLoading}
    />
  );
};
