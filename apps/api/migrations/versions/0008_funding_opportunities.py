"""track research grants and funding opportunities
Revision ID: 0008
Revises: 0007
"""
from alembic import op
revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None

def upgrade() -> None:
    op.execute("""CREATE TABLE funding_opportunities (
      id UUID PRIMARY KEY,
      workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
      category TEXT NOT NULL,
      title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 240),
      organisation TEXT NOT NULL CHECK (char_length(organisation) BETWEEN 1 AND 240),
      amount TEXT,
      opens_label TEXT,
      deadline_at TIMESTAMPTZ,
      deadline_type TEXT NOT NULL DEFAULT 'Not announced',
      eligibility_notes TEXT,
      priority TEXT NOT NULL DEFAULT 'medium' CHECK (priority IN ('high','medium','low')),
      status TEXT NOT NULL DEFAULT 'not_started' CHECK (status IN
        ('not_started','researching','preparing','submitted','awarded','rejected','not_eligible')),
      date_applied TIMESTAMPTZ,
      next_action TEXT,
      official_link TEXT,
      other_source TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      version BIGINT NOT NULL DEFAULT 1,
      deleted_at TIMESTAMPTZ
    )""")
    op.execute("CREATE INDEX idx_funding_opportunities_workspace ON funding_opportunities (workspace_id, deadline_at, updated_at)")

def downgrade() -> None:
    op.execute("DROP INDEX idx_funding_opportunities_workspace")
    op.execute("DROP TABLE funding_opportunities")
