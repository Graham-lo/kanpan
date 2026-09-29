-- 主力订单流：给 0031 搬过来的挂着的行补上消失量（2026-09-29，订单簿压测第四轮收尾）。
--
-- 0031 之前的进程从不落挂着的单的 vanished_notional（只有结束时才写），所以搬进 orderflow_live 的
-- 几千行这一列全是 NULL，只有那一单后来有变动、被新进程重写过才会补上；停机时刷的只是 seen_ms。
-- 读回时代码对 NULL 的兜底是 max(初始名义 − 当前名义, 已成交, 0)，这里把同一条规则落到表里，
-- 让「成交 ≤ 消失」在库里也成立，不再靠内存里的钳制。只碰 NULL 的行，重复执行是空操作。
UPDATE orderflow_live
   SET vanished_notional = GREATEST(initial_notional - notional, filled_notional, 0)
 WHERE vanished_notional IS NULL;
