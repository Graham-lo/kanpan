-- Public market evidence only. Importer must validate the exact model/render provenance.
CREATE TABLE market_features (
 id uuid PRIMARY KEY, market text NOT NULL, symbol text NOT NULL, timeframe text NOT NULL,
 start_at bigint NOT NULL, end_at bigint NOT NULL, bars_count integer NOT NULL,
 model_id text NOT NULL, render_version text NOT NULL, embedding vector(192) NOT NULL,
 input_hash text NOT NULL, source text NOT NULL, published boolean NOT NULL DEFAULT false,
 CHECK(start_at<end_at), CHECK(bars_count BETWEEN 3 AND 1500)
);
CREATE INDEX market_features_scope ON market_features(market,timeframe,end_at) WHERE published;
CREATE TABLE review_searches (
 user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,id uuid NOT NULL,
 query jsonb NOT NULL, status text NOT NULL DEFAULT 'queued',
 candidates jsonb, position integer NOT NULL DEFAULT 0, checked integer NOT NULL DEFAULT 0,
 items jsonb NOT NULL DEFAULT '[]', error text, lease_id uuid, lease_until timestamptz,
 attempts integer NOT NULL DEFAULT 0,next_at timestamptz NOT NULL DEFAULT now(),
 created_at timestamptz NOT NULL DEFAULT now(),expires_at timestamptz NOT NULL DEFAULT now()+interval '24 hours',
 PRIMARY KEY(user_id,id)
);
CREATE TABLE search_dispatch (
 user_id uuid PRIMARY KEY REFERENCES account_users(id) ON DELETE CASCADE,next_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE review_saved_matches (
 user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,id uuid NOT NULL,
 match jsonb NOT NULL,source_search uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 deleted boolean NOT NULL DEFAULT false,revision bigint NOT NULL DEFAULT 1,
 PRIMARY KEY(user_id,id)
);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['review_searches','review_saved_matches'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY personal_owner ON %I USING (user_id = nullif(current_setting(''kanpan.user_id'',true),'''')::uuid) WITH CHECK (user_id = nullif(current_setting(''kanpan.user_id'',true),'''')::uuid)',t);
 END LOOP;
END $$;
