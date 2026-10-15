"""research entities become synchronizable: workspace scope, status lists, exports

Revision ID: 0005
Revises: 0004

Every synchronized entity carries workspace_id (Spec 6.1). The status value lists the
spec left open are fixed here (decision 0003).
"""

from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None

SCOPED = ("milestones", "reviews", "review_items", "analysis_records", "experiment_entries")

UP = [
    *[f"ALTER TABLE {t} ADD COLUMN workspace_id UUID NOT NULL REFERENCES workspaces(id)"
      for t in SCOPED],
    *[f"CREATE INDEX idx_{t}_workspace ON {t} (workspace_id, updated_at)" for t in SCOPED],
    """ALTER TABLE milestones
      ADD CONSTRAINT milestones_mode_check CHECK (progress_mode IN ('manual','weighted')),
      ADD CONSTRAINT milestones_weight_check CHECK (weight IS NULL OR weight > 0)""",
    "ALTER TABLE review_stages ADD COLUMN created_at TIMESTAMPTZ NOT NULL DEFAULT now()",
    # Positions are rewritten when stages are reordered; checked after each statement.
    """ALTER TABLE review_stages DROP CONSTRAINT review_stages_review_id_position_key,
      DROP CONSTRAINT review_stages_review_id_name_key,
      ADD CONSTRAINT review_stages_review_id_position_key UNIQUE (review_id, position)
      DEFERRABLE INITIALLY DEFERRED,
      ADD CONSTRAINT review_stages_review_id_name_key UNIQUE (review_id, name)
      DEFERRABLE INITIALLY DEFERRED""",
    """ALTER TABLE review_items
      ADD CONSTRAINT review_items_decision_check
      CHECK (decision IS NULL OR decision IN ('include','exclude','maybe'))""",
    """ALTER TABLE analysis_records
      ADD CONSTRAINT analysis_records_status_check CHECK (status IN
        ('planned','running','succeeded','failed','blocked','archived')),
      ADD CONSTRAINT analysis_records_language_check
        CHECK (language IS NULL OR language IN ('r','python'))""",
    """ALTER TABLE experiment_entries
      ADD CONSTRAINT experiment_entries_template_check
      CHECK (template_type IS NULL OR template_type IN ('qpcr','primer_design'))""",
    "CREATE INDEX idx_tasks_milestone ON tasks (milestone_id)",
    """CREATE TABLE exports (
      id UUID PRIMARY KEY,
      workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
      requested_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      format TEXT NOT NULL CHECK (format IN ('json','csv')),
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','ready','failed')),
      content BYTEA,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      expires_at TIMESTAMPTZ
    )""",
]

DOWN = [
    "DROP TABLE exports",
    "DROP INDEX idx_tasks_milestone",
    "ALTER TABLE experiment_entries DROP CONSTRAINT experiment_entries_template_check",
    """ALTER TABLE analysis_records DROP CONSTRAINT analysis_records_language_check,
      DROP CONSTRAINT analysis_records_status_check""",
    "ALTER TABLE review_items DROP CONSTRAINT review_items_decision_check",
    """ALTER TABLE review_stages DROP CONSTRAINT review_stages_review_id_position_key,
      DROP CONSTRAINT review_stages_review_id_name_key,
      ADD CONSTRAINT review_stages_review_id_position_key UNIQUE (review_id, position),
      ADD CONSTRAINT review_stages_review_id_name_key UNIQUE (review_id, name)""",
    "ALTER TABLE review_stages DROP COLUMN created_at",
    """ALTER TABLE milestones DROP CONSTRAINT milestones_weight_check,
      DROP CONSTRAINT milestones_mode_check""",
    *[f"DROP INDEX idx_{t}_workspace" for t in SCOPED],
    *[f"ALTER TABLE {t} DROP COLUMN workspace_id" for t in SCOPED],
]


def upgrade() -> None:
    for stmt in UP:
        op.execute(stmt)


def downgrade() -> None:
    for stmt in DOWN:
        op.execute(stmt)
