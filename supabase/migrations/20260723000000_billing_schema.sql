-- 1. Create the billing subscription enum types
CREATE TYPE subscription_status AS ENUM ('trialing', 'active', 'past_due', 'canceled', 'suspended');
CREATE TYPE subscription_tier AS ENUM ('tier_1', 'tier_2', 'tier_3');

-- 2. Create the fleets table as the primary B2B tenant anchor
CREATE TABLE IF NOT EXISTS public.fleets (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    name TEXT,
    stripe_customer_id TEXT UNIQUE,
    stripe_subscription_id TEXT UNIQUE,
    status subscription_status DEFAULT 'trialing' NOT NULL,
    tier subscription_tier DEFAULT 'tier_1' NOT NULL,
    trial_start_date TIMESTAMPTZ DEFAULT NOW(),
    trial_end_date TIMESTAMPTZ DEFAULT NOW() + INTERVAL '30 days',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Backfill existing fleets based on current profiles
-- This ensures existing users don't break when we add the FK constraint
INSERT INTO public.fleets (id, name, status, tier)
SELECT DISTINCT fleet_id, 'Legacy Fleet ' || substr(fleet_id::text, 1, 8), 'active'::subscription_status, 'tier_3'::subscription_tier
FROM public.profiles
WHERE fleet_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- 4. Enforce referential integrity
ALTER TABLE public.profiles
    ADD CONSTRAINT fk_profiles_fleet_id
    FOREIGN KEY (fleet_id) REFERENCES public.fleets(id) ON DELETE CASCADE;

-- 5. Row Level Security for Fleets
ALTER TABLE public.fleets ENABLE ROW LEVEL SECURITY;

-- Everyone in the fleet can view the fleet's basic details and subscription status
CREATE POLICY "Users can view their own fleet details" ON public.fleets
    FOR SELECT USING (
        id = (SELECT fleet_id FROM profiles WHERE profiles.id = auth.uid())
        OR public.get_auth_user_role() = 'super_admin'
    );

-- Only super_admin can update fleets (Edge functions will use service role which bypasses RLS)
CREATE POLICY "Only super_admin can update fleets" ON public.fleets
    FOR UPDATE USING (
        public.get_auth_user_role() = 'super_admin'
    );

-- 6. Trigger to automatically create a fleet when a fleet_manager signs up
-- Note: In this system, fleets are created explicitly or by default for new accounts.
-- If an admin registers, we should ideally provision a fleet for them.
-- For now, relying on edge functions or application logic during onboarding.
