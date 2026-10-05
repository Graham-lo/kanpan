-- 美元指数（venue `macro`）的 K 线。和 hourly_close / daily_close 一样是公开行情，不开 RLS。
-- 永久保留，不滚动删：一年 1m 约 36 万行、5m 7 万、1h 6 千、1d 260，十年也不到 50 MB。
-- 只存四档（1m 5m 1h 1d），其余周期读的时候聚（见 src/venues/macro_index/bars.rs）。
-- 1d 的 open_time 是交易日（美东 18:00 → 17:00）当天的 00:00 UTC，不是 UTC 零点切出来的一天。
-- source：1 = CNBC 官方 K 线；0 = 报价拼出来的、或从更细的档聚出来的。官方行只会被官方行改写。
CREATE TABLE IF NOT EXISTS macro_bars (
 symbol text NOT NULL,
 interval text NOT NULL CHECK (interval IN ('1m','5m','1h','1d')),
 open_time bigint NOT NULL,
 open double precision NOT NULL,
 high double precision NOT NULL,
 low double precision NOT NULL,
 close double precision NOT NULL,
 source smallint NOT NULL DEFAULT 0 CHECK (source IN (0,1)),
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (symbol,interval,open_time)
);
