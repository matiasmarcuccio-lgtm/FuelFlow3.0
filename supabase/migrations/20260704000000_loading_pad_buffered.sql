-- 1. Añadir la columna materializada para el polígono holgado
ALTER TABLE projects 
ADD COLUMN IF NOT EXISTS loading_pad_buffered GEOMETRY(Polygon, 4326);

-- 2. Crear la función que calcula el buffer de 5 metros automáticamente
CREATE OR REPLACE FUNCTION calculate_buffered_loading_pad()
RETURNS TRIGGER 
LANGUAGE plpgsql
AS $$
BEGIN
    -- Si hay un polígono, inflarlo 5 metros (casteando a geography para precisión métrica)
    IF NEW.loading_pad_geometry IS NOT NULL THEN
        NEW.loading_pad_buffered := ST_Buffer(
            NEW.loading_pad_geometry::geography, 
            5.0 -- Tolerancia de histéresis en metros
        )::geometry;
    ELSE
        NEW.loading_pad_buffered := NULL;
    END IF;
    
    RETURN NEW;
END;
$$;

-- 3. Anclar el trigger para que PostGIS trabaje solo en las escrituras
DROP TRIGGER IF EXISTS trigger_buffer_loading_pad ON projects;
CREATE TRIGGER trigger_buffer_loading_pad
    BEFORE INSERT OR UPDATE OF loading_pad_geometry ON projects
    FOR EACH ROW
    EXECUTE FUNCTION calculate_buffered_loading_pad();
