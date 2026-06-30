-- 1. Crear el bucket 'compliance_docs' (si no existe)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) 
VALUES (
  'compliance_docs', 
  'compliance_docs', 
  false, 
  5242880, -- 5MB limit
  ARRAY['application/pdf', 'image/jpeg', 'image/png']
)
ON CONFLICT (id) DO UPDATE SET 
  public = false, 
  file_size_limit = 5242880, 
  allowed_mime_types = ARRAY['application/pdf', 'image/jpeg', 'image/png'];

-- 2. Políticas de Seguridad (RLS ya viene habilitado por defecto en storage.objects)

-- 3. Crear Políticas de Seguridad
-- Política: Los usuarios autenticados pueden subir archivos a su propia "carpeta" (donde el prefijo es su UUID)
DROP POLICY IF EXISTS "Users can upload their own compliance docs" ON storage.objects;
CREATE POLICY "Users can upload their own compliance docs" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'compliance_docs' AND 
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Política: Los usuarios pueden leer sus propios archivos
DROP POLICY IF EXISTS "Users can read their own compliance docs" ON storage.objects;
CREATE POLICY "Users can read their own compliance docs" ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'compliance_docs' AND 
  (storage.foldername(name))[1] = auth.uid()::text
);
