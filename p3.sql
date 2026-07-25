CREATE POLICY "RLS_Profiles_Read_Jurisdiction" ON public.profiles
FOR SELECT TO authenticated
USING (
    auth.uid() = id
    OR
    (
        EXISTS (
            SELECT 1 FROM public.profiles as viewer
            WHERE viewer.id = auth.uid()
            AND viewer.role IN ('supervisor', 'fleet_manager', 'super_admin')
            AND viewer.fleet_id = public.profiles.fleet_id
        )
    )
    OR
    (
        EXISTS (
            SELECT 1 FROM public.profiles as admin
            WHERE admin.id = auth.uid() AND admin.role = 'super_admin'
        )
    )
);

CREATE POLICY "RLS_Profiles_Update_Self" ON public.profiles
FOR UPDATE TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);
