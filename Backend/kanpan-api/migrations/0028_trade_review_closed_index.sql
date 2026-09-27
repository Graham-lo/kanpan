-- no-transaction
-- 交易复盘的列表（`GET /v1/native-review/records?kind=trade`）按平仓时间倒序翻页，持仓中的排最前。
-- 部分索引只收交易复盘那几行，观点复盘的写入不背它；排序键与 review.rs 里的查询逐字一致。
CREATE INDEX CONCURRENTLY IF NOT EXISTS review_records_trade_closed ON review_records(user_id,(COALESCE((record#>>'{round,closedAt}')::bigint,9223372036854775807)) DESC,id DESC) WHERE record->>'kind'='trade';
