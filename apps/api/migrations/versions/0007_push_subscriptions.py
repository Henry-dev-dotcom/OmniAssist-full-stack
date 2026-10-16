"""web push subscriptions per device (decision 0006)

Revision ID: 0007
Revises: 0006
"""

from alembic import op

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """CREATE TABLE push_subscriptions (
          endpoint TEXT PRIMARY KEY,
          user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          p256dh TEXT NOT NULL,
          auth TEXT NOT NULL,
          created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )"""
    )
    op.execute("CREATE INDEX idx_push_subscriptions_user ON push_subscriptions (user_id)")


def downgrade() -> None:
    op.execute("DROP TABLE push_subscriptions")
