-- FASE 2: FILTRADO ESTRICTO DE MERCADO DE CARGAS (BIDDING)
-- Regla de Negocio: El sistema no puede mostrar ofertas que físicamente o legalmente el conductor no puede cumplir.

CREATE OR REPLACE FUNCTION matches_contractor_profile(driver_uuid UUID, offer_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    driver_asset_4x4 BOOLEAN;
    driver_asset_radius DECIMAL(4,2);
    offer_requires_4x4 BOOLEAN;
    offer_max_radius DECIMAL(4,2);
BEGIN
    -- Obtenemos el vehículo activo asignado al driver
    SELECT has_4x4_traction, turning_radius_m INTO driver_asset_4x4, driver_asset_radius
    FROM assets WHERE driver_id = driver_uuid AND is_active = true LIMIT 1;

    -- Obtenemos los requisitos de la oferta
    SELECT requires_4x4_traction, max_turn_radius_m INTO offer_requires_4x4, offer_max_radius
    FROM load_offers WHERE id = offer_id;

    -- Si el conductor no tiene un vehículo asignado, no ve ninguna oferta que tenga requisitos especiales
    IF driver_asset_4x4 IS NULL THEN
        driver_asset_4x4 := false;
    END IF;

    -- Evaluamos la física del vehículo contra la obra
    IF offer_requires_4x4 = true AND driver_asset_4x4 = false THEN
        RETURN false;
    END IF;

    IF offer_max_radius IS NOT NULL AND (driver_asset_radius IS NULL OR driver_asset_radius > offer_max_radius) THEN
        RETURN false;
    END IF;

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Actualizamos el RLS de load_offers para aplicar el filtro
DROP POLICY IF EXISTS operator_view_policy ON load_offers;

-- Nueva política: Un operador puede ver las ofertas si están ABIERTAS y cumplen con su perfil,
-- O si la oferta ya le fue ASIGNADA a él.
CREATE POLICY operator_view_policy ON load_offers
FOR SELECT
USING (
    (status = 'BIDDING_OPEN' AND matches_contractor_profile(auth.uid(), id))
    OR 
    (id IN (SELECT load_offer_id FROM assignments WHERE operator_id = auth.uid()))
);
