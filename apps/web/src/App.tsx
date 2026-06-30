import React from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { BrowserRouter, Routes, Route, Outlet } from 'react-router-dom'
import { ExceptionProvider } from './context/ExceptionContext'
import { Sidebar } from './components/layout/Sidebar'
import { StickyExceptionHeader } from './components/layout/StickyExceptionHeader'
import { LiveOps } from './pages/LiveOps'
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

const queryClient = new QueryClient()

const AppLayout = () => {
  return (
    <div className="flex h-screen w-screen bg-slate-900 text-slate-200 overflow-hidden font-sans">
      <Sidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <StickyExceptionHeader />
        <main className="flex-1 relative overflow-hidden flex flex-col">
          <Outlet />
        </main>
      </div>
    </div>
  )
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <ExceptionProvider>
        <BrowserRouter>
          <Routes>
            {/* Public Auth Routes */}
            <Route path="/login" element={<Login />} />
            <Route path="/register" element={<Register />} />
            <Route path="/auth/callback" element={<AuthCallback />} />
            
            {/* Protected Command Center Routes */}
            <Route path="/" element={<ProtectedRoute><AppLayout /></ProtectedRoute>}>
              <Route index element={<LiveOps />} />
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
    </QueryClientProvider>
  )
}

export default App
