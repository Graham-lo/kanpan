-- 同步变更日志的截断水位（2026-09-24 深度审查 A3）。
--
-- sync_changes 从 0001 起只进不出，每个人每改一次就多一行。maintenance 从这一版起把
-- 30 天前的变更删掉（每个人最新的那一行永远留着，bootstrap 的游标靠它），并把删掉的
-- 最大 sequence 记在这里。/v1/sync/changes 收到的游标低于这个水位，说明它要的那一段
-- 已经不在了——回 410 cursor_expired，客户端重新 bootstrap，而不是悄悄漏掉一段改动。
--
-- 一个人一行，只增不减（写的时候取 GREATEST）。和同步表一样挂 FORCE RLS + personal_owner。
-- 全部 IF NOT EXISTS / DROP POLICY IF EXISTS：重跑无害。新表不涉及旧表的锁。
CREATE TABLE IF NOT EXISTS sync_change_floors (
 user_id uuid PRIMARY KEY REFERENCES account_users(id) ON DELETE CASCADE,
 sequence bigint NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE sync_change_floors ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_change_floors FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS personal_owner ON sync_change_floors;
CREATE POLICY personal_owner ON sync_change_floors USING (user_id = nullif(current_setting('kanpan.user_id',true),'')::uuid) WITH CHECK (user_id = nullif(current_setting('kanpan.user_id',true),'')::uuid);
