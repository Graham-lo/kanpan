-- no-transaction
-- 0044 的 (base,end_ms,first_seen_ms) 以它为前缀，用到它的读法与清理都改走 0044，留着只是每次写多维护一份。
DROP INDEX CONCURRENTLY IF EXISTS orderflow_orders_end;
