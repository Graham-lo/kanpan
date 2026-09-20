-- 提醒模块的两张表。都是**新建的空表**，所以这一条走普通事务：
-- `migrations/README.md` 里那条「建索引一律 CONCURRENTLY」是为了不在**已有**的大表上
-- 拿锁；新表在本条迁移之前根本不存在，没有人能在写它，主键与唯一约束顺带建出来的索引
-- 扫的是零行。也正因为如此这里不写任何独立的 CREATE INDEX——需要的查询形状都由主键
-- 前缀覆盖（见下），一条语句都不用额外加。
--
-- 两张表都挂 FORCE ROW LEVEL SECURITY + personal_owner 策略，和 0001 里的同步表一样：
-- 运行期角色 kanpan_app 既不是属主也没有 BYPASSRLS，所以「忘了带 user_id 条件」在这里
-- 不会变成串号，而是查不到行。评估器跑在 worker 里，一样要先 AppState::personal(owner)
-- 开事务、set_config('kanpan.user_id', …)，没有例外通道。

-- 活动提醒的物化表：`alerts` 同步对象的一份按「评估器要什么」重排的投影。
-- 为什么不直接查 sync_objects：评估器每来一帧 1m K 线就要按品种找活动提醒，而
-- sync_objects 的 body 是 jsonb、主键是 (user_id,collection,id)，按 symbol/status 过滤
-- 只能全扫加解 json。这张表只存活动评估要用的那几列，写同步的时候顺手刷新。
--
-- alert_id 是同步对象的 id 原样（binance/usd_m/<SYMBOL>/<alertID>），不是 uuid：
-- 同步协议里对象 id 就是文本，拆出 uuid 只会多一次解析和一类对不上的可能。
--
-- kind / condition / title 三列是表 2.2 里有、而任务清单没点名的：评估器要按 kind 只看
-- drawing、要跳过 condition='close'（本轮只实现 touch），推送标题又是客户端生成好放在
-- 提醒对象里的，不存下来就得在触发的那一刻回头去 sync_objects 解一次 json。
--
-- 主键 (user_id,alert_id) 同时是评估器那条查询的索引：它按用户逐个开事务
-- （RLS 要求如此），条件是 user_id 等值 + status='active'，前导列正好对上。
-- 用户上限十来个、每人提醒几十条，剩下的过滤走顺序扫完全够。
CREATE TABLE alert_watches (
 user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 alert_id text NOT NULL,
 kind text NOT NULL,
 symbol text NOT NULL,
 market text NOT NULL DEFAULT 'binance/usd_m',
 drawing_id text,
 lines jsonb NOT NULL DEFAULT '[]',
 condition text NOT NULL DEFAULT 'touch',
 title text NOT NULL DEFAULT '',
 armed_at bigint NOT NULL DEFAULT 0,
 status text NOT NULL DEFAULT 'active',
 fired_at bigint,
 fired_price double precision,
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,alert_id)
);

-- 推送 token 挂在设备上。account_sessions 才是设备那一行（device_id 在会话上），
-- 会话会被顶掉、会过期，token 不该跟着一起消失——同一台设备重新登录还是同一枚
-- token，所以这里只存 device_id 而不外键到会话。
--
-- 主键 (user_id,device_id,kind) 就是「同一设备同 kind 覆盖」那条唯一性，只不过是**按账号**
-- 唯一。没有再加一条 UNIQUE(device_id,kind) 是故意的：那条跨账号的唯一约束在 RLS 下会
-- 变成一个死结——一台手机换账号登录时，新账号看不见旧账号那一行（策略把它挡住了），
-- ON CONFLICT 碰上一行自己看不见的记录，Postgres 直接报错，于是注册 token 这一步会对
-- 换过账号的设备**永远失败**。按账号唯一则每一步都在自己能看见的行里完成。
-- 代价是同一台设备上退过登的旧账号会留一行；那一行推出去的通知苹果照收，但它推的是
-- 旧账号的提醒。这个账号上还活着的提醒本来就不多，而且 app 卸载重装后 token 变了、
-- 旧行会在第一次 410 时被删掉（见 src/apns.rs 的 Outcome::Gone）。
-- user_id 同时是 RLS 策略要过滤的那一列，主键前导它，「这个人的所有 token」走主键前缀。
CREATE TABLE device_push_tokens (
 user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 device_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('alerts','liveActivity','widget')),
 environment text NOT NULL CHECK(environment IN ('production','sandbox')),
 token text NOT NULL,
 activity_id text,
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,device_id,kind)
);

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['alert_watches','device_push_tokens'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY personal_owner ON %I USING (user_id = nullif(current_setting(''kanpan.user_id'',true),'''')::uuid) WITH CHECK (user_id = nullif(current_setting(''kanpan.user_id'',true),'''')::uuid)',t);
 END LOOP;
END $$;
