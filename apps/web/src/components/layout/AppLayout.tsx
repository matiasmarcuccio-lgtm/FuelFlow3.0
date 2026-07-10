import React from 'react';
import { Outlet } from 'react-router-dom';
import { Sidebar } from './Sidebar';
import { StickyExceptionHeader } from './StickyExceptionHeader';
import { useRealtimeSync } from '../../hooks/useRealtimeSync';

export const AppLayout = () => {
  useRealtimeSync();
  return (
    <div className="flex h-screen w-screen bg-background text-foreground overflow-hidden font-sans">
      <Sidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <StickyExceptionHeader />
        <main className="flex-1 relative overflow-hidden flex flex-col">
          <Outlet />
        </main>
      </div>
    </div>
  );
};
