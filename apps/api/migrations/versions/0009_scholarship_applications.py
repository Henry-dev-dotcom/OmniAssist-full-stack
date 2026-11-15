"""track scholarship applications and their document checklists
Revision ID: 0009
Revises: 0008
"""
from alembic import op
revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None

_STEP = "('not_started','in_progress','requested','registered','pending','ready','submitted')"


def upgrade() -> None:
    op.execute(f"""CREATE TABLE scholarship_applications (
      id UUID PRIMARY KEY,
      workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      region TEXT NOT NULL CHECK (char_length(region) BETWEEN 1 AND 80),
      university TEXT NOT NULL CHECK (char_length(university) BETWEEN 1 AND 240),
      program TEXT,
      scheme TEXT,
      portal_link TEXT,
      opens_label TEXT,
      deadline_at TIMESTAMPTZ,
      status TEXT NOT NULL DEFAULT 'not_started' CHECK (status IN
        ('not_started','preparing','submitted','under_review','accepted','rejected')),
      documents_required TEXT,
      cv_status TEXT NOT NULL DEFAULT 'not_started' CHECK (cv_status IN {_STEP}),
      transcripts_status TEXT NOT NULL DEFAULT 'not_started' CHECK (transcripts_status IN {_STEP}),
      letter_status TEXT NOT NULL DEFAULT 'not_started' CHECK (letter_status IN {_STEP}),
      references_status TEXT NOT NULL DEFAULT 'not_started' CHECK (references_status IN {_STEP}),
      portal_status TEXT NOT NULL DEFAULT 'not_started' CHECK (portal_status IN {_STEP}),
      funding TEXT,
      notes TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      version BIGINT NOT NULL DEFAULT 1,
      deleted_at TIMESTAMPTZ
    )""")
    op.execute(
        "CREATE INDEX idx_scholarship_applications_workspace "
        "ON scholarship_applications (workspace_id, region, deadline_at, updated_at)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX idx_scholarship_applications_workspace")
    op.execute("DROP TABLE scholarship_applications")
