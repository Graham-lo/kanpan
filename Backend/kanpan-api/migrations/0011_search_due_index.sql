-- no-transaction
-- 一个文件只放一条语句：不在事务里的迁移，sqlx 仍旧是把整份文件当**一条**简单查询发过去，
-- 而 Postgres 对「一条简单查询里有多个命令」会自己包一个隐式事务——那样 CONCURRENTLY
-- 又会报 `cannot run inside a transaction block`。所以删索引那条另开了 0012。

-- worker 领搜索任务的那条查询（src/search.rs 的 run_one）实测是 Seq Scan：
--   WHERE user_id=$1 AND status IN ('queued','running') AND next_at<=now()
--         AND expires_at>now() AND (lease_until IS NULL OR lease_until<now())
--   ORDER BY created_at,id FOR UPDATE SKIP LOCKED LIMIT 1
-- 0004 建表时只有 PRIMARY KEY(user_id,id)，排序列 created_at 不在里面，于是每次轮询
-- （每秒一次）都要把这个人的全部搜索历史读出来再排一遍。前导等值列 user_id 之后直接接
-- ORDER BY 的两列，规划器就能边扫边出序、LIMIT 1 立刻停。
-- 部分索引的谓词只留还没结束的那几条：搜索做完会变成 done/failed/cancelled，
-- 那些行永远不该再被领，也就不必占索引。
CREATE INDEX CONCURRENTLY IF NOT EXISTS review_searches_due
 ON review_searches(user_id,created_at,id) WHERE status IN ('queued','running');
