CREATE TABLE IF NOT EXISTS app_environment (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  environment text NOT NULL CHECK (environment IN ('local', 'test', 'staging', 'production'))
);
CREATE TABLE IF NOT EXISTS account (
  id uuid PRIMARY KEY,
  display_name text NOT NULL,
  practice_finishes integer NOT NULL DEFAULT 0 CHECK (practice_finishes >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS account_identity (
  provider text NOT NULL CHECK (provider IN ('dev', 'google')),
  issuer text NOT NULL,
  subject text NOT NULL,
  account_id uuid NOT NULL REFERENCES account(id),
  PRIMARY KEY (provider, issuer, subject)
);
CREATE TABLE IF NOT EXISTS guest_profile (
  id uuid PRIMARY KEY,
  practice_finishes integer NOT NULL DEFAULT 0 CHECK (practice_finishes >= 0),
  merged_account_id uuid REFERENCES account(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS game_session (
  token_hash char(64) PRIMARY KEY,
  environment text NOT NULL,
  account_id uuid REFERENCES account(id),
  guest_id uuid REFERENCES guest_profile(id),
  pending_guest_id uuid REFERENCES guest_profile(id),
  provider text CHECK (provider IN ('dev', 'google')),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((account_id IS NULL) <> (guest_id IS NULL)),
  CHECK ((account_id IS NULL AND provider IS NULL) OR (account_id IS NOT NULL AND provider IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS game_session_expiry ON game_session(expires_at);
CREATE TABLE IF NOT EXISTS auth_attempt (
  id uuid PRIMARY KEY,
  session_hash char(64) NOT NULL REFERENCES game_session(token_hash),
  provider text NOT NULL,
  nonce_hash char(64) NOT NULL,
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS guest_merge (
  merge_id uuid PRIMARY KEY,
  guest_id uuid NOT NULL UNIQUE REFERENCES guest_profile(id),
  account_id uuid NOT NULL REFERENCES account(id),
  practice_finishes integer NOT NULL CHECK (practice_finishes >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);
