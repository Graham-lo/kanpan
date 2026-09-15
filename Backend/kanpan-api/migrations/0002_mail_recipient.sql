ALTER TABLE account_mail ADD COLUMN recipient_hash text;
CREATE INDEX account_mail_recipient ON account_mail(recipient_hash);
