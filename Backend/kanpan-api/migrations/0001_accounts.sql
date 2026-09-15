CREATE EXTENSION IF NOT EXISTS vector;

-- Authentication tables are accessed only by the identity layer, before personal RLS context exists.
CREATE TABLE account_users (
 id uuid PRIMARY KEY, email text UNIQUE NOT NULL, password_hash text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), disabled_at timestamptz
);
CREATE TABLE account_challenges (
 id uuid PRIMARY KEY, email text NOT NULL, purpose text NOT NULL CHECK(purpose IN ('register','reset')),
 password_hash text, code_hash text NOT NULL, attempts integer NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
 consumed_at timestamptz
);
CREATE INDEX account_challenge_email ON account_challenges(email,purpose,created_at DESC);
CREATE TABLE account_limits (
 key text PRIMARY KEY, failures integer NOT NULL DEFAULT 0,
 window_start timestamptz NOT NULL DEFAULT now(), locked_until timestamptz
);
CREATE TABLE account_sessions (
 id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 device_id uuid NOT NULL, device_name text NOT NULL, binding_hash text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), seen_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL, revoked_at timestamptz
);
CREATE INDEX account_sessions_user ON account_sessions(user_id);
CREATE TABLE account_tokens (
 token_hash text PRIMARY KEY, session_id uuid NOT NULL REFERENCES account_sessions(id) ON DELETE CASCADE,
 kind text NOT NULL CHECK(kind IN ('access','refresh')), expires_at timestamptz NOT NULL,
 used_at timestamptz, request_id uuid, response_sealed text
);
CREATE INDEX account_tokens_session ON account_tokens(session_id);
CREATE TABLE account_mail (
 id uuid PRIMARY KEY, payload_sealed text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 attempts integer NOT NULL DEFAULT 0, next_attempt timestamptz NOT NULL DEFAULT now(),
 sent_at timestamptz
);
CREATE TABLE account_deletions (
 user_id uuid PRIMARY KEY, requested_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz
);

CREATE TABLE sync_objects (
 user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 collection text NOT NULL, id text NOT NULL, body jsonb NOT NULL DEFAULT '{}',
 fields jsonb NOT NULL DEFAULT '{}', revision bigint NOT NULL DEFAULT 0,
 deleted boolean NOT NULL DEFAULT false, generation bigint NOT NULL DEFAULT 0,
 changed_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(user_id,collection,id)
);
CREATE TABLE sync_changes (
 sequence bigserial PRIMARY KEY, user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 collection text NOT NULL, object_id text NOT NULL, revision bigint NOT NULL,
 deleted boolean NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sync_changes_owner_cursor ON sync_changes(user_id,sequence);
CREATE TABLE sync_operations (
 user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE, id uuid NOT NULL,
 digest text NOT NULL, result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,id)
);
CREATE TABLE sync_snapshots (
 id bigserial PRIMARY KEY,user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 collection text NOT NULL, object_id text NOT NULL, snapshot jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE sync_claims (
 batch_id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES account_users(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now()
);

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['sync_objects','sync_changes','sync_operations','sync_snapshots','sync_claims'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY personal_owner ON %I USING (user_id = nullif(current_setting(''kanpan.user_id'',true),'''')::uuid) WITH CHECK (user_id = nullif(current_setting(''kanpan.user_id'',true),'''')::uuid)',t);
 END LOOP;
END $$;
