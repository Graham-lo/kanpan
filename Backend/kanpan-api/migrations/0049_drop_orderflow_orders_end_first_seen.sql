-- no-transaction
-- 0048 的 orderflow_orders_end_covering 是同样的键再挂上读出去的列，读与清理（end_ms < 截止）都用它，这条多余。
DROP INDEX CONCURRENTLY IF EXISTS orderflow_orders_end_first_seen;
