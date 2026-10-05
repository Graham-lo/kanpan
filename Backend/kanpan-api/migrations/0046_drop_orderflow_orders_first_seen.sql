-- no-transaction
-- (base,first_seen_ms) 只有 `range_sql` 第二路用过，而那一路正是选了它才慢（见 0044）；0044 之后没有读法再要它。
-- 删掉免得规划器在参数估不准时又挑回它，也少维护一份。
DROP INDEX CONCURRENTLY IF EXISTS orderflow_orders_first_seen;
