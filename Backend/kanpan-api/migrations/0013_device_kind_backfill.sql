-- 0010 给 account_sessions 加 device_kind 时用的是 DEFAULT 'phone'，于是所有升级前就
-- 在线的会话——包括 iPad 和电脑——都被记成了手机。这本来只是「我的设备」里显示不准，
-- 但「每个账号每类设备只许一台在线」是按 device_kind 顶人的（src/auth.rs 里那条
-- revoked_reason='replaced' 的 UPDATE），于是这个人下一次用手机登录，会顺手把他那台被
-- 误记成手机的 iPad 顶下线，而他完全不知道为什么。
--
-- 0010 一个字都不能改（已经在线上应用过，sqlx 校验的是校验和），所以在这里按会话自己
-- 报上来的设备名回填。只动仍然记着 'phone' 的行：新版客户端登录时会自己带正确的
-- device_kind，那些行不该被名字猜测覆盖；同一条迁移重复执行也不会有第二次效果。
--
-- 这是两条普通的 UPDATE，行级锁、走事务，所以和 0011/0012 那两条 CONCURRENTLY 分开写
-- （不在事务里的迁移中途失败不回滚，把 UPDATE 放进去就等于放弃了它的原子性）。
-- account_sessions 只有活跃会话那么几行，不是大表。
--
-- 名字是客户端填的自由文本，猜不出来的就留在 'phone'：把一台真手机误判成平板同样会踢
-- 错人，宁可不动。两条谓词互不重叠（iPad 里没有 mac/pc/windows/desktop）。
UPDATE account_sessions SET device_kind='tablet'
 WHERE device_kind='phone' AND device_name ~* '(ipad|tablet|\ypad\y)';

UPDATE account_sessions SET device_kind='desktop'
 WHERE device_kind='phone' AND device_name ~* '(macbook|imac|\ymac\y|\ypc\y|windows|desktop)';
