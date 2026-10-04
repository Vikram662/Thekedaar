CREATE TABLE IF NOT EXISTS installs (
  install_id TEXT PRIMARY KEY,
  customer_id TEXT NOT NULL,
  name TEXT NOT NULL,
  phone TEXT,
  subscription_id TEXT UNIQUE,
  subscription_status TEXT NOT NULL DEFAULT 'none',
  subscription_created_at INTEGER,
  latest_payment_id TEXT,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS installs_subscription_idx
  ON installs(subscription_id);