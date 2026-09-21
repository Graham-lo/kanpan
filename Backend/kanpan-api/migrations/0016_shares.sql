-- 两张新空表在同一个普通事务中创建；索引随新表创建，不锁已有表。
CREATE TABLE friendships (
 user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 friend_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,friend_id), CHECK(user_id<>friend_id)
);
CREATE TABLE shares (
 id text PRIMARY KEY,
 from_user uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 to_user uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 symbol text NOT NULL, market text NOT NULL DEFAULT 'binance/usd_m', interval text NOT NULL,
 view_from bigint NOT NULL, view_to bigint NOT NULL,
 drawings jsonb NOT NULL, alerted jsonb NOT NULL DEFAULT '[]',
 reply_to text REFERENCES shares(id) ON DELETE SET NULL,
 shot bytea CHECK(octet_length(shot)<=307200),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 opened_at timestamptz, kept_at timestamptz,
 CHECK(from_user<>to_user), CHECK(view_from<view_to)
);
CREATE INDEX shares_inbox ON shares(to_user,created_at DESC);
ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE friendships FORCE ROW LEVEL SECURITY;
CREATE POLICY personal_owner ON friendships
 USING(user_id=nullif(current_setting('kanpan.user_id',true),'')::uuid)
 WITH CHECK(user_id=nullif(current_setting('kanpan.user_id',true),'')::uuid);
ALTER TABLE shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE shares FORCE ROW LEVEL SECURITY;
CREATE POLICY share_participant ON shares
 USING(from_user=nullif(current_setting('kanpan.user_id',true),'')::uuid OR to_user=nullif(current_setting('kanpan.user_id',true),'')::uuid)
 WITH CHECK(from_user=nullif(current_setting('kanpan.user_id',true),'')::uuid OR to_user=nullif(current_setting('kanpan.user_id',true),'')::uuid);
