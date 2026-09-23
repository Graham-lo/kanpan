-- 复盘记录的「补一张图」（P3.7）。
--
-- 和 0015 那张「记一笔时自动截的图」是两件事：那张一条记录只有一张、跟着记录一起生、
-- 主键就是记录；这里是人事后从相册里挑的，一条记录最多三张，各有各的 id，能单删。
-- 上限（单张解码后 ≤ 5 MiB、每条 ≤ 3 张）在路由层卡（`review.rs` 的 `attachment_put`），
-- 这里不写 CHECK：超限要回一个客户端认得的错误码，而不是一个约束冲突。
--
-- 存在数据库里的理由同 0015：十来个用户，一条最多 15 MiB，随现有的 pg_dump 备份走，
-- 不为它单开一套对象存储。外键连着 review_records 的复合主键，记录没了图跟着走。
--
-- RLS 同复盘那几张表：FORCE + personal_owner，运行期角色不是属主、没有 BYPASSRLS，
-- 「忘了带 user_id 条件」的查询查不到别人的行，而不是串号。
CREATE TABLE review_attachments (
 user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 id uuid NOT NULL,
 record_id uuid NOT NULL,
 mime text NOT NULL,
 bytes bytea NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,id),
 FOREIGN KEY(user_id,record_id) REFERENCES review_records(user_id,id) ON DELETE CASCADE
);
CREATE INDEX review_attachments_record ON review_attachments(user_id,record_id,created_at);
ALTER TABLE review_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_attachments FORCE ROW LEVEL SECURITY;
CREATE POLICY personal_owner ON review_attachments USING (user_id = nullif(current_setting('kanpan.user_id',true),'')::uuid) WITH CHECK (user_id = nullif(current_setting('kanpan.user_id',true),'')::uuid);
