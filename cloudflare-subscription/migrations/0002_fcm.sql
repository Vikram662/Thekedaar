ALTER TABLE installs ADD COLUMN fcm_token TEXT;
ALTER TABLE installs ADD COLUMN platform TEXT;
ALTER TABLE installs ADD COLUMN notification_updated_at INTEGER;

CREATE INDEX IF NOT EXISTS installs_fcm_token_idx ON installs(fcm_token);
