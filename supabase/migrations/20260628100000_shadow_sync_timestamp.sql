-- Migración: Sincronización en la Sombra (Shadow Sync)
-- Agregamos la columna para recibir el timestamp forense directamente del hardware del operador

ALTER TABLE public.load_offers 
  ADD COLUMN IF NOT EXISTS completed_at_local TIMESTAMP WITH TIME ZONE;
