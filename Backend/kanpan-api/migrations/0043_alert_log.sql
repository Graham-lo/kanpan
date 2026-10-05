-- 提醒触发记录（2026-10-05）。提醒「触发即删」：响完同步对象和 alert_watches 那一行都没了，
-- 用户想回头看「上周哪几条响过、响在多少」无处可查。这张表只追加：服务端判响（alerts::record_fired，
-- 币安 / Coinbase / 美元指数三支、条件提醒、复盘到点都走它）与客户端判响后同步上来的
-- 「非 fired → fired」（alerts::materialize）各写一行。
-- 留 30 天，maintenance::cleanup 每小时按批删过期的（src/maintenance.rs 的 PERSONAL）。
-- alert_id 与 alert_watches 一样是文本（`binance/usd_m/BTCUSDT/<id>`），不是 uuid。
-- symbol 存完整品种键（`binance/usd_m/BTCUSDT`、`macro/index/DXY`），客户端 InstrumentID.canonical 认这一种。
-- kind 照 alert_watches.kind 原样存：drawing / price / condition / reviewDue。
-- (user_id, alert_id, fired_at) 唯一：同一次触发两条路都写（或客户端重推）只留一行。
-- 新的空表，索引直接在迁移事务里建，不需要 CONCURRENTLY。
CREATE TABLE IF NOT EXISTS alert_log (
 user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 id uuid PRIMARY KEY,
 alert_id text NOT NULL,
 kind text NOT NULL,
 symbol text NOT NULL,
 title text NOT NULL DEFAULT '',
 condition text NOT NULL DEFAULT '',
 fired_at bigint NOT NULL,
 fired_price double precision,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (user_id,alert_id,fired_at)
);
CREATE INDEX IF NOT EXISTS alert_log_user_fired ON alert_log(user_id,fired_at DESC);

ALTER TABLE alert_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE alert_log FORCE ROW LEVEL SECURITY;
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='alert_log' AND policyname='personal_owner') THEN
  CREATE POLICY personal_owner ON alert_log
   USING (user_id = nullif(current_setting('kanpan.user_id',true),'')::uuid)
   WITH CHECK (user_id = nullif(current_setting('kanpan.user_id',true),'')::uuid);
 END IF;
END $$;
