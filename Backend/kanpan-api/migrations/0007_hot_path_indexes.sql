-- Indexes for the paths that run on every poll or every sync, not new state.
-- Every index stays owner-scoped so it cannot leak across accounts.

-- Worker claim: user_id + due order, and only jobs still open. The partial
-- predicate keeps the index the size of the backlog rather than of all history.
CREATE INDEX review_jobs_due ON review_jobs(user_id,next_at,id) WHERE NOT finished;

-- The schedulers poll every second and only ever ask "who is due"; without this
-- each poll sorts the whole dispatch table.
CREATE INDEX review_dispatch_due ON review_dispatch(next_at,user_id);
CREATE INDEX search_dispatch_due ON search_dispatch(next_at,user_id);

-- Episode lookup on submit: exact owner/symbol/market, then the newest window
-- that contains the anchor. Leading equality columns first, then the ORDER BY.
CREATE INDEX review_episodes_window ON review_episodes(user_id,symbol,market,anchor_at DESC,id DESC);

-- /v1/sync/changes joins sync_objects on its primary key and bootstrap paginates
-- on (user_id,collection,id), so both are already served by that key. What the
-- key cannot serve is the prefix scan: starts_with() is only a range scan under
-- pattern ops when the database is not in the C collation.
CREATE INDEX sync_objects_prefix ON sync_objects(user_id,collection,id text_pattern_ops);
