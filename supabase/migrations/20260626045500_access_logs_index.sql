-- Índice B-Tree para optimizar la paginación masiva del rastro forense
CREATE INDEX IF NOT EXISTS idx_access_logs_timestamp ON access_logs USING btree (timestamp DESC);
