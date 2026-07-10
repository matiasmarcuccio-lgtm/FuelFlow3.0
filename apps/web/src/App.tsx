import React from 'react'
import { PersistQueryClientProvider } from '@tanstack/react-query-persist-client'
import { queryClient, idbPersister } from './lib/queryClient'
import { BrowserRouter, Routes, Route, Outlet } from 'react-router-dom'
import { ExceptionProvider } from './context/ExceptionContext'
import { Sidebar } from './components/layout/Sidebar'
import { StickyExceptionHeader } from './components/layout/StickyExceptionHeader'
import { useRealtimeSync } from './hooks/useRealtimeSync'
import { JITSiteDashboard } from './pages/JITSiteDashboard'
import { HealthDashboard } from './pages/HealthDashboard'
import { SystemConfig } from './pages/SystemConfig'
import { ComplianceReport } from './pages/ComplianceReport'
import { BuilderDashboard } from './pages/BuilderDashboard'
import { FleetDashboard } from './pages/FleetDashboard'
import { ForensicSearchEngine } from './pages/ForensicSearchEngine'
import { UserManagement } from './pages/UserManagement'
import { SettingsDashboard } from './pages/SettingsDashboard'
import { ProtectedRoute } from './components/ProtectedRoute'
import Login from './pages/Login'
import Register from './pages/Register'
import AuthCallback from './pages/AuthCallback'
import { HandoverContainer } from './features/handover/HandoverContainer'
import { ScannerPresenter } from './features/handover/ScannerPresenter'
import { KinematicKiosk } from './features/kiosk/KinematicKiosk'
import { WeighbridgeDashboard } from './pages/WeighbridgeDashboard'
import { AnalyticsContainer } from './features/dashboard/AnalyticsContainer'
import { ProjectGatekeeper } from './components/ProjectGatekeeper';

// Wrapper para extraer parámetros de la URL para el HandoverContainer
import { useParams } from 'react-router-dom';
import { useCrewRosterSync } from './features/handover/useCrewRosterSync';

const HandoverRouteWrapper = () => {
  const { projectId, assetId } = useParams();
  
  // Hidratación proactiva (Si hay red, actualiza la caché, si no, usa la de idb-keyval)
  useCrewRosterSync(projectId || null);

  if (!projectId || !assetId) return <div className="p-8 text-white">Missing parameters</div>;

  return <HandoverContainer projectId={projectId} assetId={assetId} />;
};

function App() {
  return (
    <PersistQueryClientProvider 
      client={queryClient} 
      persistOptions={{ 
        persister: idbPersister,
        maxAge: 1000 * 60 * 60 * 24 * 7, // 7 días de retención garantizada
        // @ts-ignore - Forzamos el volcado inmediato al disco físico de la tablet
        throttleTime: 0,
        dehydrateOptions: {
          shouldDehydrateMutation: (mutation) => true,
          shouldDehydrateQuery: (query) => true
        }
      }}
    >
      <ExceptionProvider>
        <BrowserRouter>
          <Routes>
            {/* Public Auth Routes */}
            <Route path="/login" element={<Login />} />
            <Route path="/register" element={<Register />} />
            <Route path="/auth/callback" element={<AuthCallback />} />
            
            {/* Rutas dedicadas tipo Kiosk */}
            <Route 
              path="/scan" 
              element={
                <ProtectedRoute>
                  <ScannerPresenter />
                </ProtectedRoute>
              } 
            />
            <Route 
              path="/handover/:projectId/:assetId" 
              element={
                <ProtectedRoute>
                  <HandoverRouteWrapper />
                </ProtectedRoute>
              } 
            />
            
            {/* Kiosk Mode Cinemático (Tablet en Cabina) */}
            <Route 
              path="/kiosk/:projectId/:assetId" 
              element={
                <ProtectedRoute>
                  <KinematicKiosk />
                </ProtectedRoute>
              } 
            />
            
            <Route 
              path="/weighbridge/:projectId?" 
              element={
                <ProtectedRoute>
                  <WeighbridgeDashboard />
                </ProtectedRoute>
              } 
            />
            
            {/* Protected Command Center Routes */}
            <Route path="/" element={<ProtectedRoute><ProjectGatekeeper /></ProtectedRoute>}>
              <Route index element={<JITSiteDashboard />} />
              <Route path="analytics/:projectId?" element={<AnalyticsContainer />} />
              <Route path="builder" element={<BuilderDashboard />} />
              <Route path="fleet" element={<FleetDashboard />} />
              <Route path="health" element={<HealthDashboard />} />
              <Route path="config" element={<SystemConfig />} />
              <Route path="compliance" element={<ComplianceReport />} />
              <Route path="forensic" element={<ForensicSearchEngine />} />
              <Route path="users" element={<UserManagement />} />
              <Route path="settings" element={<SettingsDashboard />} />
            </Route>
          </Routes>
        </BrowserRouter>
      </ExceptionProvider>
    </PersistQueryClientProvider>
  )
}

export default App
