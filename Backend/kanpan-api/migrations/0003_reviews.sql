CREATE TABLE review_episodes (
 user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 id uuid NOT NULL, symbol text NOT NULL, market text NOT NULL,
 anchor_at bigint NOT NULL, end_at bigint NOT NULL, PRIMARY KEY(user_id,id)
);
CREATE TABLE review_records (
 user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 id uuid NOT NULL, record jsonb NOT NULL, submitted bigint NOT NULL,
 symbol text NOT NULL, timeframe text NOT NULL, range_start bigint NOT NULL, range_end bigint NOT NULL,
 episode_id uuid NOT NULL, group_pending boolean NOT NULL DEFAULT false,
 source_verified boolean NOT NULL DEFAULT false, source_hash text,
 feature vector(192), feature_version text, checkpoint bigint,
 assessment_revision bigint NOT NULL DEFAULT 0, reflection_assessment_revision bigint,
 changed_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(user_id,id),
 FOREIGN KEY(user_id,episode_id) REFERENCES review_episodes(user_id,id)
);
CREATE INDEX review_records_page ON review_records(user_id,submitted DESC,id DESC);
CREATE INDEX review_records_symbol ON review_records(user_id,symbol,submitted DESC);
CREATE TABLE review_operations (
 user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 id uuid NOT NULL, digest text NOT NULL, result jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(user_id,id)
);
CREATE TABLE review_events (
 user_id uuid NOT NULL, id uuid NOT NULL, record_id uuid NOT NULL,
 kind text NOT NULL, body jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,id), FOREIGN KEY(user_id,record_id) REFERENCES review_records(user_id,id) ON DELETE CASCADE
);
CREATE TABLE review_jobs (
 user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 id uuid NOT NULL, record_id uuid NOT NULL, kind text NOT NULL,
 next_at timestamptz NOT NULL DEFAULT now(), lease_id uuid, lease_until timestamptz,
 attempts integer NOT NULL DEFAULT 0, finished boolean NOT NULL DEFAULT false,
 PRIMARY KEY(user_id,id), UNIQUE(user_id,record_id,kind),
 FOREIGN KEY(user_id,record_id) REFERENCES review_records(user_id,id) ON DELETE CASCADE
);
-- Scheduler sees account IDs and due times only, never personal job bodies or record IDs.
CREATE TABLE review_dispatch (
 user_id uuid PRIMARY KEY REFERENCES account_users(id) ON DELETE CASCADE,
 next_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE provider_budgets (
 egress_id text NOT NULL, market text NOT NULL, window_start timestamptz NOT NULL DEFAULT date_trunc('minute',now()),
 used integer NOT NULL DEFAULT 0, blocked_until timestamptz NOT NULL DEFAULT '-infinity',
 PRIMARY KEY(egress_id,market)
);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['review_episodes','review_records','review_operations','review_events','review_jobs'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY personal_owner ON %I USING (user_id = nullif(current_setting(''kanpan.user_id'',true),'''')::uuid) WITH CHECK (user_id = nullif(current_setting(''kanpan.user_id'',true),'''')::uuid)',t);
 END LOOP;
END $$;
