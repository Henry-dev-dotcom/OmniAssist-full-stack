"""initial core schema (Implementation Plan section 4.1 plus supporting tables)

Revision ID: 0001
Revises:
"""

from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None

TS = "TIMESTAMPTZ NOT NULL DEFAULT now()"
# Columns every synchronized table carries.
SYNC = f"""created_at {TS}, updated_at {TS},
  version BIGINT NOT NULL DEFAULT 1, deleted_at TIMESTAMPTZ"""

UP = f"""
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE project_category AS ENUM
  ('personal','thesis','grant','review','experiment','analysis','software');
CREATE TYPE project_status AS ENUM
  ('planned','in_progress','on_hold','complete','archived');
CREATE TYPE task_status AS ENUM
  ('inbox','planned','in_progress','complete','snoozed','cancelled','archived');
CREATE TYPE task_priority AS ENUM ('low','normal','high','critical');
CREATE TYPE milestone_status AS ENUM
  ('not_started','in_progress','at_risk','blocked','complete','archived');

CREATE TABLE users (
  id UUID PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  timezone TEXT NOT NULL DEFAULT 'UTC',
  preferences JSONB NOT NULL DEFAULT '{{}}'::jsonb,
  created_at {TS}, updated_at {TS}
);

CREATE TABLE workspaces (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES users(id),
  name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
  archived_at TIMESTAMPTZ,
  {SYNC}
);

CREATE TABLE workspace_members (
  workspace_id UUID NOT NULL REFERENCES workspaces(id),
  user_id UUID NOT NULL REFERENCES users(id),
  role TEXT NOT NULL DEFAULT 'owner' CHECK (role IN ('owner')),
  created_at {TS},
  PRIMARY KEY (workspace_id, user_id)
);

CREATE TABLE projects (
  id UUID PRIMARY KEY,
  workspace_id UUID NOT NULL REFERENCES workspaces(id),
  name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
  category project_category NOT NULL,
  status project_status NOT NULL DEFAULT 'planned',
  description TEXT,
  start_at TIMESTAMPTZ,
  target_at TIMESTAMPTZ,
  progress_mode TEXT NOT NULL DEFAULT 'manual',
  progress_value NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (progress_value BETWEEN 0 AND 100),
  {SYNC},
  CHECK (target_at IS NULL OR start_at IS NULL OR target_at >= start_at)
);

CREATE TABLE milestones (
  id UUID PRIMARY KEY,
  project_id UUID NOT NULL REFERENCES projects(id),
  parent_id UUID REFERENCES milestones(id),
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 240),
  description TEXT,
  status milestone_status NOT NULL DEFAULT 'not_started',
  due_at TIMESTAMPTZ,
  progress_value NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (progress_value BETWEEN 0 AND 100),
  weight NUMERIC(10,2),
  progress_mode TEXT NOT NULL DEFAULT 'manual',
  completed_at TIMESTAMPTZ,
  {SYNC}
);

CREATE TABLE milestone_dependencies (
  milestone_id UUID NOT NULL REFERENCES milestones(id),
  depends_on_id UUID NOT NULL REFERENCES milestones(id),
  PRIMARY KEY (milestone_id, depends_on_id),
  CHECK (milestone_id <> depends_on_id)
);

CREATE TABLE tasks (
  id UUID PRIMARY KEY,
  workspace_id UUID NOT NULL REFERENCES workspaces(id),
  project_id UUID REFERENCES projects(id),
  milestone_id UUID REFERENCES milestones(id),
  parent_task_id UUID REFERENCES tasks(id),
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 240),
  description TEXT,
  status task_status NOT NULL DEFAULT 'inbox',
  priority task_priority NOT NULL DEFAULT 'normal',
  due_at TIMESTAMPTZ,
  estimated_minutes INTEGER CHECK (estimated_minutes IS NULL OR estimated_minutes > 0),
  recurrence_rule TEXT,
  completed_at TIMESTAMPTZ,
  {SYNC}
);

CREATE TABLE tags (
  id UUID PRIMARY KEY,
  workspace_id UUID NOT NULL REFERENCES workspaces(id),
  name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
  {SYNC},
  UNIQUE (workspace_id, name)
);

CREATE TABLE task_tags (
  task_id UUID NOT NULL REFERENCES tasks(id),
  tag_id UUID NOT NULL REFERENCES tags(id),
  PRIMARY KEY (task_id, tag_id)
);

CREATE TABLE routines (
  id UUID PRIMARY KEY,
  workspace_id UUID NOT NULL REFERENCES workspaces(id),
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 240),
  recurrence_rule TEXT NOT NULL,
  starts_at TIMESTAMPTZ,
  duration_minutes INTEGER CHECK (duration_minutes IS NULL OR duration_minutes > 0),
  {SYNC}
);

CREATE TABLE time_blocks (
  id UUID PRIMARY KEY,
  workspace_id UUID NOT NULL REFERENCES workspaces(id),
  task_id UUID REFERENCES tasks(id),
  project_id UUID REFERENCES projects(id),
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 240),
  category TEXT NOT NULL,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'planned',
  {SYNC},
  CHECK (ends_at > starts_at)
);

CREATE TABLE reviews (
  id UUID PRIMARY KEY,
  project_id UUID NOT NULL REFERENCES projects(id),
  name TEXT NOT NULL,
  description TEXT,
  {SYNC}
);

CREATE TABLE review_stages (
  id UUID PRIMARY KEY,
  review_id UUID NOT NULL REFERENCES reviews(id),
  name TEXT NOT NULL,
  position INTEGER NOT NULL,
  archived_at TIMESTAMPTZ,
  UNIQUE (review_id, position),
  UNIQUE (review_id, name)
);

CREATE TABLE review_items (
  id UUID PRIMARY KEY,
  review_id UUID NOT NULL REFERENCES reviews(id),
  stage_id UUID NOT NULL REFERENCES review_stages(id),
  title TEXT NOT NULL,
  source_identifier TEXT,
  decision TEXT,
  reviewer TEXT,
  tags JSONB NOT NULL DEFAULT '[]'::jsonb,
  notes TEXT,
  external_url TEXT,
  {SYNC}
);

CREATE TABLE review_item_events (
  id UUID PRIMARY KEY,
  review_item_id UUID NOT NULL REFERENCES review_items(id),
  from_stage_id UUID REFERENCES review_stages(id),
  to_stage_id UUID REFERENCES review_stages(id),
  decision TEXT,
  actor_id UUID NOT NULL REFERENCES users(id),
  created_at {TS}
);

CREATE TABLE analysis_records (
  id UUID PRIMARY KEY,
  project_id UUID NOT NULL REFERENCES projects(id),
  milestone_id UUID REFERENCES milestones(id),
  title TEXT NOT NULL,
  purpose TEXT,
  language TEXT,
  repository_url TEXT,
  branch_name TEXT,
  commit_ref TEXT,
  data_source_ref TEXT,
  environment TEXT,
  status TEXT NOT NULL DEFAULT 'planned',
  last_run_at TIMESTAMPTZ,
  result_summary TEXT,
  error_details TEXT,
  next_action TEXT,
  {SYNC}
);

CREATE TABLE experiment_entries (
  id UUID PRIMARY KEY,
  project_id UUID NOT NULL REFERENCES projects(id),
  template_type TEXT,
  title TEXT NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL,
  objective TEXT,
  protocol TEXT,
  variables TEXT,
  materials TEXT,
  observations TEXT,
  deviations TEXT,
  result_summary TEXT,
  next_steps TEXT,
  state TEXT NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','finalized')),
  revision_number INTEGER NOT NULL DEFAULT 1,
  {SYNC}
);

CREATE TABLE experiment_revisions (
  id UUID PRIMARY KEY,
  entry_id UUID NOT NULL REFERENCES experiment_entries(id),
  revision_number INTEGER NOT NULL,
  snapshot JSONB NOT NULL,
  actor_id UUID NOT NULL REFERENCES users(id),
  created_at {TS},
  UNIQUE (entry_id, revision_number)
);

CREATE TABLE notifications (
  id UUID PRIMARY KEY,
  workspace_id UUID NOT NULL REFERENCES workspaces(id),
  entity_type TEXT NOT NULL,
  entity_id UUID NOT NULL,
  remind_at TIMESTAMPTZ NOT NULL,
  urgency TEXT NOT NULL DEFAULT 'normal',
  channel TEXT NOT NULL DEFAULT 'push',
  delivery_status TEXT NOT NULL DEFAULT 'scheduled',
  {SYNC}
);

CREATE TABLE attachments (
  id UUID PRIMARY KEY,
  workspace_id UUID NOT NULL REFERENCES workspaces(id),
  entity_type TEXT NOT NULL,
  entity_id UUID NOT NULL,
  file_name TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  size_bytes BIGINT NOT NULL CHECK (size_bytes >= 0),
  storage_key TEXT,
  checksum TEXT,
  upload_state TEXT NOT NULL DEFAULT 'pending',
  {SYNC}
);

CREATE TABLE activity_events (
  id UUID PRIMARY KEY,
  workspace_id UUID NOT NULL REFERENCES workspaces(id),
  actor_id UUID NOT NULL REFERENCES users(id),
  entity_type TEXT NOT NULL,
  entity_id UUID NOT NULL,
  action TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{{}}'::jsonb,
  created_at {TS}
);

CREATE TABLE audit_events (
  id UUID PRIMARY KEY,
  workspace_id UUID REFERENCES workspaces(id),
  actor_id UUID REFERENCES users(id),
  entity_type TEXT,
  entity_id UUID,
  action TEXT NOT NULL,
  request_id TEXT,
  created_at {TS}
);

CREATE TABLE sync_changes (
  sequence BIGSERIAL PRIMARY KEY,
  workspace_id UUID NOT NULL REFERENCES workspaces(id),
  entity_type TEXT NOT NULL,
  entity_id UUID NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('create','update','delete')),
  entity_version BIGINT NOT NULL,
  payload JSONB,
  created_at {TS}
);

CREATE TABLE sync_mutations (
  mutation_id UUID PRIMARY KEY,
  workspace_id UUID NOT NULL REFERENCES workspaces(id),
  actor_id UUID NOT NULL REFERENCES users(id),
  entity_type TEXT NOT NULL,
  entity_id UUID NOT NULL,
  operation TEXT NOT NULL,
  base_version BIGINT,
  request_hash TEXT NOT NULL,
  result JSONB,
  created_at {TS}
);

CREATE TABLE sync_conflicts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id),
  entity_type TEXT NOT NULL,
  entity_id UUID NOT NULL,
  base_version BIGINT,
  local_payload JSONB NOT NULL,
  server_payload JSONB NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  created_at {TS},
  resolved_at TIMESTAMPTZ
);

CREATE INDEX idx_projects_workspace_updated ON projects(workspace_id, updated_at);
CREATE INDEX idx_tasks_workspace_updated ON tasks(workspace_id, updated_at);
CREATE INDEX idx_tasks_workspace_due ON tasks(workspace_id, due_at, status);
CREATE INDEX idx_tasks_project_status ON tasks(project_id, status);
CREATE INDEX idx_milestones_project_status ON milestones(project_id, status);
CREATE INDEX idx_review_items_review_stage ON review_items(review_id, stage_id);
CREATE INDEX idx_activity_workspace_created ON activity_events(workspace_id, created_at);
CREATE INDEX idx_audit_workspace_created ON audit_events(workspace_id, created_at);
CREATE INDEX idx_sync_changes_workspace_sequence ON sync_changes(workspace_id, sequence);
CREATE UNIQUE INDEX idx_sync_mutations_workspace_id ON sync_mutations(workspace_id, mutation_id);
"""

TABLES = """sync_conflicts sync_mutations sync_changes audit_events activity_events attachments
notifications experiment_revisions experiment_entries analysis_records review_item_events
review_items review_stages reviews time_blocks routines task_tags tags tasks
milestone_dependencies milestones projects workspace_members workspaces users""".split()
TYPES = "milestone_status task_priority task_status project_status project_category".split()


def upgrade() -> None:
    # asyncpg runs one statement per call, so split the script (no ';' inside literals).
    for statement in UP.split(";"):
        if statement.strip():
            op.execute(statement)


def downgrade() -> None:
    for table in TABLES:
        op.execute(f"DROP TABLE IF EXISTS {table} CASCADE")
    for t in TYPES:
        op.execute(f"DROP TYPE IF EXISTS {t}")
