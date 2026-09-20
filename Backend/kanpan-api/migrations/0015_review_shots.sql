-- 「记一笔」自动带上的那张图（§4.3）。
--
-- 一条记录最多一张，所以主键就是 (user_id, record_id)：不需要附件 id，也不需要列表
-- 查询——它永远是「拿这一条记录的那张图」。外键连着 review_records 的复合主键，
-- 记录作废/删号时图跟着走，不会留下没人认领的字节。
--
-- 图存在数据库里而不是对象存储：上限 2 MiB、总共十来个用户，一张 2× 缩放的 PNG
-- 三四百 KB，攒一年也就几百兆；为它单开一套对象存储的凭证、生命周期与备份，
-- 比这点字节贵得多。bytea 随现有的 pg_dump 备份一起走。
--
-- RLS 和 0003 里那几张复盘表同一套：FORCE + personal_owner，运行期角色既不是属主
-- 也没有 BYPASSRLS，「忘了带 user_id 条件」在这里查不到行而不是串号。
CREATE TABLE review_shots (
 user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 record_id uuid NOT NULL,
 mime text NOT NULL,
 bytes bytea NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,record_id),
 FOREIGN KEY(user_id,record_id) REFERENCES review_records(user_id,id) ON DELETE CASCADE
);
ALTER TABLE review_shots ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_shots FORCE ROW LEVEL SECURITY;
CREATE POLICY personal_owner ON review_shots USING (user_id = nullif(current_setting('kanpan.user_id',true),'')::uuid) WITH CHECK (user_id = nullif(current_setting('kanpan.user_id',true),'')::uuid);
