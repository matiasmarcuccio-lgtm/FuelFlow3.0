BEGIN;
ALTER TABLE public.asset_assignments ADD COLUMN IF NOT EXISTS master_order_id UUID REFERENCES public.master_orders(id);

ALTER TABLE public.master_orders ADD COLUMN IF NOT EXISTS fleet_id UUID REFERENCES public.fleets(id);
ALTER TABLE public.master_orders ADD COLUMN IF NOT EXISTS client_id UUID REFERENCES public.clients(id);
ALTER TABLE public.master_orders ADD COLUMN IF NOT EXISTS description TEXT;

COMMIT;
