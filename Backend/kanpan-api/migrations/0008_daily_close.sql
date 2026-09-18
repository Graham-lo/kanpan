-- Daily closes behind /v1/market/sector-history: the 5-day and 20-day sector
-- windows need one number per contract per day, nothing more.
--
-- Public market data, so this table is shaped like market_features and not like
-- the personal ones: no owner column and no row level security, because there
-- is no owner to scope it to. The runtime role still neither owns it nor
-- bypasses RLS; ops/install.py grants that role SELECT/INSERT/UPDATE/DELETE on
-- every table in the schema after the admin role has migrated, and the daily
-- collector needs all four (insert, upsert, and the retention deletes).
CREATE TABLE daily_close (
 symbol text NOT NULL,
 day date NOT NULL,
 close double precision NOT NULL,
 quote_volume double precision NOT NULL,
 PRIMARY KEY(symbol,day)
);

-- Both readers walk a day, not a symbol: the route asks for the two days
-- `asof-5` and `asof-20` across every contract, and retention deletes rows
-- older than a year. The primary key leads with `symbol`, so it serves neither.
CREATE INDEX daily_close_day ON daily_close(day);
