-- Activa la tubería de salida hacia Edge Functions configurando los parámetros globales de la base de datos

-- 1. URL de la Edge Function 'process-outbox' (Reemplazar <PROJECT_REF> con el ID real de Supabase)
ALTER DATABASE postgres SET "app.settings.edge_function_outbox_url" TO 'https://<PROJECT_REF>.supabase.co/functions/v1/process-outbox';

-- 2. Clave criptográfica para la Guillotina Zero-Trust (B2B_WEBHOOK_SECRET)
-- Este secreto se usará en PostgreSQL para generar la firma HMAC-SHA256
ALTER DATABASE postgres SET "app.settings.b2b_webhook_secret" TO 'TU_SECRETO_CRIPTOGRAFICO_GENERADO_ALEATORIAMENTE';

-- 3. Para aplicar estos cambios, es necesario reiniciar las conexiones o recargar la configuración:
-- En Supabase, esto se aplica inmediatamente para las nuevas sesiones. 
-- Asegúrate de que el pg_cron tenga permiso para leer estas variables si es que está configurado como bg worker.

-- NOTA: Como alternativa a las variables de entorno de base de datos puras,
-- Supabase Vault permite manejar secretos de forma más segura.
-- Si Vault está habilitado, los secretos se inyectarían así (y el RPC de pg_cron los leería de vault.decrypted_secrets):
-- SELECT vault.create_secret('TU_SECRETO_CRIPTOGRAFICO_GENERADO_ALEATORIAMENTE', 'b2b_webhook_secret');
