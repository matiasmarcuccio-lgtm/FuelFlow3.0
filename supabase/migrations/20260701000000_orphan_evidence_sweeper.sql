-- Migration: Orphan Evidence Sweeper
-- Purpose: Ensures that files uploaded to Supabase Storage that failed to link to the database
-- due to client network failures are cleaned up after 48 hours to prevent storage bloat.

-- Create a function that sweeps orphaned files
CREATE OR REPLACE FUNCTION fn_sweep_orphan_evidence()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    -- Delete objects in the docket_evidence bucket older than 48 hours
    -- that do not have a matching path in the load_offers table.
    -- (storage.objects.name contains the file path e.g. "offer_id/file.jpg")
    WITH deleted AS (
        DELETE FROM storage.objects
        WHERE bucket_id = 'docket_evidence'
          AND created_at < NOW() - INTERVAL '48 hours'
          AND name NOT IN (
              SELECT docket_image_path 
              FROM public.load_offers 
              WHERE docket_image_path IS NOT NULL
          )
        RETURNING id
    )
    SELECT count(*) INTO deleted_count FROM deleted;

    RAISE NOTICE 'Orphan Evidence Sweeper executed. Deleted % orphaned files.', deleted_count;
END;
$$;

-- Note: To fully automate this in Supabase, you would use pg_cron:
-- SELECT cron.schedule('sweep_orphan_evidence_cron', '0 0 * * *', 'SELECT fn_sweep_orphan_evidence()');
