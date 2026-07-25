import { useState } from 'react';
import { useUserRoles, type UserProjectRole } from '../hooks/useUserRole';
import { useAuth } from '../context/AuthContext';
import { RoleBasedRouter } from './RoleBasedRouter';
import { Activity, ShieldCheck, CreditCard, Lock } from 'lucide-react';

export const ProjectGatekeeper = () => {
    const { data: roles, isLoading, isError } = useUserRoles();
    const { userRole, fleetStatus, loading: authLoading } = useAuth();
    const [selectedProject, setSelectedProject] = useState<UserProjectRole | null>(null);

    if (isLoading || authLoading) {
        return (
            <div className="w-screen h-screen bg-background flex flex-col items-center justify-center text-on-surface">
                <Activity className="w-12 h-12 text-primary animate-spin mb-4" />
                <p>Verificando credenciales de acceso...</p>
            </div>
        );
    }

    // Zero-Trust Billing Enforcement
    if (fleetStatus === 'past_due' || fleetStatus === 'canceled' || fleetStatus === 'suspended') {
        const canManageBilling = userRole === 'super_admin' || userRole === 'fleet_manager';
        
        return (
            <div className="w-screen h-screen bg-background flex flex-col items-center justify-center text-on-surface p-6 text-center">
                <Lock className="w-16 h-16 text-destructive mb-6" />
                <h1 className="text-3xl font-black uppercase tracking-widest text-foreground mb-4">
                    Licencia Comercial Suspendida
                </h1>
                
                {canManageBilling ? (
                    <div className="max-w-md w-full">
                        <p className="text-muted-foreground mb-8 text-lg">
                            La suscripción de tu flota ha caducado o el pago ha fallado. Debes regularizar tu cuenta para restaurar el acceso operativo a todos tus conductores.
                        </p>
                        <button 
                            onClick={() => window.location.href = '#/settings'} 
                            className="w-full flex items-center justify-center gap-2 bg-primary text-primary-foreground font-bold uppercase tracking-widest py-4 rounded-lg hover:bg-primary/90 transition-colors"
                        >
                            <CreditCard className="w-5 h-5" />
                            Gestionar Facturación
                        </button>
                    </div>
                ) : (
                    <div className="max-w-md">
                        <p className="text-muted-foreground text-lg p-6 bg-muted rounded-xl border border-border">
                            El acceso a la plataforma está bloqueado porque la licencia de esta flota se encuentra inactiva. 
                            <br/><br/>
                            <span className="font-bold text-foreground">Por favor, contacta a tu Administrador de Flota.</span>
                        </p>
                    </div>
                )}
            </div>
        );
    }

    if (isError || !roles || roles.length === 0) {
        return (
            <div className="w-screen h-screen bg-background flex flex-col items-center justify-center text-on-surface">
                <ShieldCheck className="w-16 h-16 text-red-500 mb-4" />
                <h1 className="text-xl font-bold text-foreground mb-2">Acceso Denegado</h1>
                <p>No tienes frentes de trabajo asignados en la Cadena de Responsabilidad.</p>
            </div>
        );
    }

    // Auto-selección si solo hay un proyecto (no hay ambigüedad)
    if (roles.length === 1) {
        return <RoleBasedRouter activeRole={roles[0]} />;
    }

    // Si ya seleccionó uno explícitamente
    if (selectedProject) {
        return <RoleBasedRouter activeRole={selectedProject} />;
    }

    // Selector explícito (Aduana) si hay múltiples proyectos
    return (
        <div className="w-screen h-screen bg-background flex flex-col items-center justify-center text-on-surface p-8">
            <div className="max-w-2xl w-full">
                <div className="mb-8 text-center">
                    <ShieldCheck className="w-16 h-16 text-primary mx-auto mb-4" />
                    <h1 className="text-3xl font-bold text-foreground mb-2">Selección de Frente de Trabajo</h1>
                    <p className="text-on-surface-variant">
                        Tu identidad está asignada a múltiples obras. Selecciona explícitamente tu ubicación física actual.
                    </p>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {roles.map((project) => (
                        <button
                            key={project.project_id}
                            onClick={() => setSelectedProject(project)}
                            className="bg-surface border border-outline-variant shadow-sm border border-outline-variant hover:border-blue-500 hover:bg-slate-750 p-6 rounded-xl flex flex-col items-start transition-all text-left group"
                        >
                            <div className="flex items-center gap-3 mb-4 w-full">
                                <div className="bg-background p-3 rounded-lg group-hover:bg-blue-900/30">
                                    <MapPin className="w-6 h-6 text-primary" />
                                </div>
                                <div>
                                    <h3 className="text-lg font-bold text-foreground">{project.projects?.name || 'Obra Desconocida'}</h3>
                                    <p className="text-xs text-outline uppercase tracking-wider">ID: {project.project_id.split('-')[0]}</p>
                                </div>
                            </div>
                            
                            <div className="w-full bg-background/50 rounded-lg p-3 flex items-center gap-2 border border-outline-variant/50">
                                <HardHat className="w-4 h-4 text-emerald-400" />
                                <span className="text-sm font-medium text-on-surface">
                                    Rol Asignado: <span className="text-foreground capitalize">{project.role}</span>
                                </span>
                            </div>
                        </button>
                    ))}
                </div>
            </div>
        </div>
    );
};
