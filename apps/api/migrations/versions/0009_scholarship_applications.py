"""track scholarship sections, schemes, applications and document checklists
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
    # A section groups applications (a country, a degree level, anything the user names).
    op.execute("""CREATE TABLE scholarship_sections (
      id UUID PRIMARY KEY,
      workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
      description TEXT,
      position INTEGER NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      version BIGINT NOT NULL DEFAULT 1,
      deleted_at TIMESTAMPTZ
    )""")
    # A removed section's name can be used again.
    op.execute(
        "CREATE UNIQUE INDEX uq_scholarship_sections_name "
        "ON scholarship_sections (workspace_id, lower(name)) WHERE deleted_at IS NULL"
    )
    op.execute(f"""CREATE TABLE scholarship_applications (
      id UUID PRIMARY KEY,
      workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      section_id UUID NOT NULL REFERENCES scholarship_sections(id) ON DELETE CASCADE,
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
        "ON scholarship_applications (workspace_id, section_id, deadline_at, updated_at)"
    )
    # A scheme is a funding route for a section (a government quota, an olympiad, a merit award).
    op.execute("""CREATE TABLE scholarship_schemes (
      id UUID PRIMARY KEY,
      workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      section_id UUID NOT NULL REFERENCES scholarship_sections(id) ON DELETE CASCADE,
      name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 240),
      organizing_body TEXT,
      coverage TEXT,
      strategy TEXT,
      position INTEGER NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      version BIGINT NOT NULL DEFAULT 1,
      deleted_at TIMESTAMPTZ
    )""")
    op.execute(
        "CREATE INDEX idx_scholarship_schemes_workspace "
        "ON scholarship_schemes (workspace_id, section_id, position)"
    )


def downgrade() -> None:
    op.execute("DROP TABLE scholarship_schemes")
    op.execute("DROP TABLE scholarship_applications")
    op.execute("DROP TABLE scholarship_sections")
