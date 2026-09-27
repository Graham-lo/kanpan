-- 品种状态通知（docs/条件提醒-协议-2026-09-27.md 第 6 节）：上新 / 将下架 / 暂停 / 恢复 / 已下架。
--
-- 三张新表，都在这份迁移里新建，不碰任何老表，所以普通事务就够。
--
-- listing_catalog：上一轮对表看到的每个品种的状态。全局表（品种表是公开数据，没有属主），
--   worker 每 10 分钟拿新表和它比，比出变化写 listing_events。第一次（空表）只建基线。
--   主键 (venue,market,symbol) 就是对表时逐个查找的键，不另加索引。
CREATE TABLE IF NOT EXISTS listing_catalog (
 venue text NOT NULL,
 market text NOT NULL,
 symbol text NOT NULL,
 -- trading / pending / halted / delisted
 state text NOT NULL,
 -- 币安永续被排上的下架时刻（毫秒）；没排就是 NULL。
 delivery_at bigint,
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(venue,market,symbol)
);

-- listing_events：比出来的每一个变化。全局表，同一个变化只有一行，推给谁由 listing_notices 记。
--   扇出只看最近 1 小时的（`at` 上的范围扫描；表里只留 30 天，每天几条到几十条，不加索引）。
CREATE TABLE IF NOT EXISTS listing_events (
 id bigserial PRIMARY KEY,
 venue text NOT NULL,
 market text NOT NULL,
 symbol text NOT NULL,
 event text NOT NULL CHECK (event IN ('listed','delistScheduled','halted','resumed','delisted')),
 delivery_at bigint,
 at bigint NOT NULL
);

-- listing_notices：谁收到过哪一条。主键 (user_id,event_id) 就是「每个变化每人只推一次」的那道闸：
--   先 INSERT … ON CONFLICT DO NOTHING，插进去了才推。也是 GET /v1/alerts/listing-notices 的数据源
--   （前导列 user_id 等值，每人几十行）。个人数据，和别的个人表一样 FORCE RLS。
CREATE TABLE IF NOT EXISTS listing_notices (
 user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 event_id bigint NOT NULL REFERENCES listing_events(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,event_id)
);
ALTER TABLE listing_notices ENABLE ROW LEVEL SECURITY;
ALTER TABLE listing_notices FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS personal_owner ON listing_notices;
CREATE POLICY personal_owner ON listing_notices
 USING (user_id = nullif(current_setting('kanpan.user_id',true),'')::uuid)
 WITH CHECK (user_id = nullif(current_setting('kanpan.user_id',true),'')::uuid);
