-- 币安权重账本分两列（2026-09-30 压测 C 路，vendor/scorebook-market/src/adapters/provider_budget.rs）：
-- `used` 照旧是整个 IP 这一分钟的权重估计（自己预留的 + 回头 x-mbx-used-weight-1m 取大），
-- 新的 `reserved` 只记 worker 自己（找相似、复盘判定、索引）这一分钟预留了多少。预留要过两道：
-- reserved 不超本类份额、used 不超整个 IP 的上限——serve 进程的订单流快照不再被扣两遍。
-- 常量默认值的 ADD COLUMN 只改目录、不重写表；这张表只有几行，锁拿不到就别干等。
SET LOCAL lock_timeout = '10s';
ALTER TABLE provider_budgets ADD COLUMN IF NOT EXISTS reserved integer NOT NULL DEFAULT 0;
