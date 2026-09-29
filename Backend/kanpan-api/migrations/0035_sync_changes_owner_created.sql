-- no-transaction
-- 与 0034 同一件事的另一半：变更日志按人、按时间截（src/sync.rs 的 prune / past_window）。
-- 现有的 sync_changes_owner_cursor 是 (user_id,sequence)，筛 created_at 只能把这个人的
-- 全部变更逐行回表再过滤；有了 (user_id,created_at)，「有没有到期的」只读几个索引页。
CREATE INDEX CONCURRENTLY IF NOT EXISTS sync_changes_owner_created
 ON sync_changes(user_id,created_at);
