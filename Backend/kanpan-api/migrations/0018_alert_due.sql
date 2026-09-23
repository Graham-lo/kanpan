-- 复盘到点（`kind='reviewDue'`）进提醒体系（P3.1）：物化表补两列。
--
-- - due_at：到期时刻（毫秒，和 armed_at / fired_at 同一把尺）。评估器每轮刷新读
--   `status='active' AND kind='reviewDue' AND due_at<=now` 的那些，置 fired 并推送。
-- - review_id：那条复盘记录的 id。推送的深链 `hkline://review/<id>` 靠它。
--
-- 两列都是可空列、都带 IF NOT EXISTS：加可空列只动系统表、不重写数据、不排队
-- （README「加列只能是可空列」那一条），ops/install.py 每次部署都跑一遍 migrate 也无妨。
-- 不建索引：查询按 user_id 逐个人开事务（RLS），主键前缀已经覆盖。
ALTER TABLE alert_watches ADD COLUMN IF NOT EXISTS due_at bigint;
ALTER TABLE alert_watches ADD COLUMN IF NOT EXISTS review_id text;
