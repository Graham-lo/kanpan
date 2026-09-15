ALTER TABLE account_challenges ADD COLUMN response_digest text;
ALTER TABLE account_challenges ADD COLUMN response_sealed text;
ALTER TABLE account_challenges ADD COLUMN response_at timestamptz;
