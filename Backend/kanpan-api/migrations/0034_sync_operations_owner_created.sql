-- no-transaction
-- 一个文件只放一条语句（见 README「0011 起：新迁移必须是无锁的」）；变更日志那一条在 0035。

-- 同步回执按人、按时间截（src/sync.rs 的 prune / past_window）：
--   WHERE user_id=$1 AND created_at<now()-30 天
-- 0001 建表时回执表只有 PRIMARY KEY(user_id,id)，id 是随机 UUID，按它走索引等于按随机顺序
-- 回表；规划器干脆 Seq Scan 整张表——每个人每小时都把所有人的回执堆页读一遍
-- （2026-09-30 线上：7876 行占 1754 页，一次冷读 1672 页）。IO 被检查点占满时，这一扫
-- 跑了 146 秒，而它是拿着这个人的同步锁跑的，他那两分钟的同步全回 503（压测 C）。
-- 前导等值列 user_id 接 created_at，「有没有到期的」只读几个索引页，删的时候也只回表到期的那几行。
CREATE INDEX CONCURRENTLY IF NOT EXISTS sync_operations_owner_created
 ON sync_operations(user_id,created_at);
