"""built-in email/password sign-in (decision 0002)

Revision ID: 0004
Revises: 0003
"""

from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


UP = [
    # subject matches users.auth_subject, which is created on first verified token.
    """CREATE TABLE local_credentials (
      subject TEXT PRIMARY KEY,
      email TEXT NOT NULL,
      display_name TEXT NOT NULL,
      password_hash TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )""",
    "CREATE UNIQUE INDEX uq_local_credentials_email ON local_credentials (lower(email))",
    # Only a SHA-256 of each refresh token is stored; a DB leak cannot replay sessions.
    """CREATE TABLE local_refresh_tokens (
      token_hash TEXT PRIMARY KEY,
      subject TEXT NOT NULL REFERENCES local_credentials (subject) ON DELETE CASCADE,
      expires_at TIMESTAMPTZ NOT NULL,
      revoked_at TIMESTAMPTZ
    )""",
    "CREATE INDEX idx_local_refresh_tokens_subject ON local_refresh_tokens (subject)",
]

DOWN = [
    "DROP TABLE local_refresh_tokens",
    "DROP TABLE local_credentials",
]


def upgrade() -> None:
    for stmt in UP:
        op.execute(stmt)


def downgrade() -> None:
    for stmt in DOWN:
        op.execute(stmt)
