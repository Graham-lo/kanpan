-- 条件提醒（docs/条件提醒-协议-2026-09-27.md）：物化表补一列 `rule`。
--
-- `kind='condition'` 的提醒不看线，看的是同步对象里的 `rule`（费率 / 持仓量 / 均线 / 大单）。
-- 评估器每一轮都要读它，不存下来就得回头去 sync_objects 解一次 json。别的 kind 这一列是 NULL。
--
-- 可空列、IF NOT EXISTS：只动系统表、不重写数据（README「加列只能是可空列」）。
-- 不加索引：条件评估那条查询是 `user_id=$1 AND status='active' AND kind='condition'`，
-- 主键 (user_id,alert_id) 的前导列已经对上，每人几十行，剩下的顺序过滤足够。
ALTER TABLE alert_watches ADD COLUMN IF NOT EXISTS rule jsonb;
