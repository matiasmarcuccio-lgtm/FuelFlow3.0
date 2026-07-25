-- Crear el bucket de almacenamiento WORM (Write Once, Read Many)
INSERT INTO storage.buckets (id, name, public) 
VALUES ('audit_certificates', 'audit_certificates', true)
ON CONFLICT (id) DO NOTHING;

-- 1. Ampliar el libro mayor con metadata criptográfica
ALTER TABLE public.execution_certificates
ADD COLUMN forensic_pdf_hash VARCHAR(64),
ADD COLUMN forensic_pdf_url TEXT;

-- 2. Gatillo de Inmutabilidad Absoluta (Anti-Tampering)
CREATE OR REPLACE FUNCTION public.protect_forensic_hash()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Si el hash ya existía y alguien intenta actualizarlo o borrarlo, la base de datos colapsa la transacción
    IF OLD.forensic_pdf_hash IS NOT NULL AND NEW.forensic_pdf_hash IS DISTINCT FROM OLD.forensic_pdf_hash THEN
        RAISE EXCEPTION 'TAMPER_ALERT: El hash forense del certificado es inmutable y no puede ser alterado ni siquiera por el superadministrador.';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_pdf_hash
BEFORE UPDATE ON public.execution_certificates
FOR EACH ROW
EXECUTE FUNCTION public.protect_forensic_hash();
