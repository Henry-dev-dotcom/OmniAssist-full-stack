"""notification delivery state: text, snooze, read and failure tracking

Revision ID: 0003
Revises: 0002
"""

from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


UP = [
    """ALTER TABLE notifications
      ADD COLUMN title TEXT NOT NULL DEFAULT '',
      ADD COLUMN offset_spec TEXT,
      ADD COLUMN snoozed_until TIMESTAMPTZ,
      ADD COLUMN sent_at TIMESTAMPTZ,
      ADD COLUMN read_at TIMESTAMPTZ,
      ADD COLUMN resolved_at TIMESTAMPTZ,
      ADD COLUMN failure_reason TEXT,
      ADD CONSTRAINT notifications_status_check CHECK (delivery_status IN
        ('scheduled','sent','dismissed','snoozed','failed','acted_on','cancelled')),
      ADD CONSTRAINT notifications_urgency_check CHECK (urgency IN
        ('low','normal','high','critical')),
      ADD CONSTRAINT notifications_channel_check CHECK (channel IN ('push','in_app','email'))""",
    """CREATE INDEX idx_notifications_due ON notifications (remind_at)
      WHERE delivery_status = 'scheduled' AND deleted_at IS NULL""",
    "CREATE INDEX idx_notifications_entity ON notifications (entity_type, entity_id)",
    "CREATE INDEX idx_notifications_workspace ON notifications (workspace_id, remind_at DESC)",
]

DOWN = [
    "DROP INDEX idx_notifications_workspace",
    "DROP INDEX idx_notifications_entity",
    "DROP INDEX idx_notifications_due",
    """ALTER TABLE notifications
      DROP CONSTRAINT notifications_channel_check,
      DROP CONSTRAINT notifications_urgency_check,
      DROP CONSTRAINT notifications_status_check,
      DROP COLUMN failure_reason, DROP COLUMN resolved_at, DROP COLUMN read_at,
      DROP COLUMN sent_at, DROP COLUMN snoozed_until, DROP COLUMN offset_spec,
      DROP COLUMN title""",
]


def upgrade() -> None:
    for stmt in UP:
        op.execute(stmt)


def downgrade() -> None:
    for stmt in DOWN:
        op.execute(stmt)
