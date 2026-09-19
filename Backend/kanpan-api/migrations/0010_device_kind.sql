-- 一个账号每一类设备同时只准一台在线：手机一类、平板一类、电脑一类。
-- 会话要记住自己是哪一类设备开的，登录时才知道该把谁顶下去。
-- 线上装着的那些包还不会发这个字段，默认值让它们照常算手机。
ALTER TABLE account_sessions ADD COLUMN device_kind text NOT NULL DEFAULT 'phone'
 CHECK (device_kind IN ('phone','tablet','desktop'));

-- 会话是怎么没的。被同类设备顶下去（replaced）要让客户端说成「这个账号在另一台
-- 手机上登录了」，和退登、踢设备、改密、注销分得开——它们仍旧是笼统的登录已失效。
ALTER TABLE account_sessions ADD COLUMN revoked_reason text
 CHECK (revoked_reason IN ('replaced','logout','device_revoked','password_change','account_deleted'));

-- 每次登录都要按 (user_id, device_kind) 找还活着的会话，活着的那几条才是热数据。
CREATE INDEX account_sessions_live_kind ON account_sessions(user_id,device_kind) WHERE revoked_at IS NULL;
