export const ERROR_CODES = [
  "VALIDATION_ERROR",
  "UNAUTHENTICATED",
  "FORBIDDEN",
  "NOT_FOUND",
  "VERSION_CONFLICT",
  "IDEMPOTENCY_KEY_REUSED",
  "DOMAIN_RULE_VIOLATION",
  "RATE_LIMITED",
  "DEPENDENCY_UNAVAILABLE",
  "INTERNAL_ERROR",
] as const;

export type ErrorCode = (typeof ERROR_CODES)[number];

export type ApiMeta = {
  request_id: string | null;
  [key: string]: unknown;
};

export type SuccessEnvelope<TData> = {
  data: TData;
  meta: ApiMeta;
};

export type ValidationFieldError = {
  field: string;
  issue: string;
};

export type ApiErrorBody = {
  code: ErrorCode;
  message: string;
  details: Record<string, unknown>;
  request_id: string | null;
  retryable: boolean;
};

export type ErrorEnvelope = {
  error: ApiErrorBody;
};

export type ProjectCategory =
  | "personal"
  | "thesis"
  | "grant"
  | "review"
  | "experiment"
  | "analysis"
  | "software";

export type ProjectStatus = "planned" | "in_progress" | "on_hold" | "complete" | "archived";
export type ProgressMode = "manual" | "weighted";

export type Project = {
  id: string;
  workspace_id: string;
  name: string;
  category: ProjectCategory;
  status: ProjectStatus;
  description: string | null;
  start_at: string | null;
  target_at: string | null;
  progress_mode: ProgressMode;
  progress_value: number;
  version: number;
  updated_at: string;
};

export type TaskStatus =
  | "inbox"
  | "planned"
  | "in_progress"
  | "complete"
  | "snoozed"
  | "cancelled"
  | "archived";
export type TaskPriority = "low" | "normal" | "high" | "critical";

export type Task = {
  id: string;
  workspace_id: string;
  project_id: string | null;
  milestone_id: string | null;
  parent_task_id: string | null;
  title: string;
  description: string | null;
  status: TaskStatus;
  priority: TaskPriority;
  due_at: string | null;
  estimated_minutes: number | null;
  recurrence_rule: string | null;
  completed_at: string | null;
  tags: string[];
  version: number;
  updated_at: string;
};

export type MilestoneStatus = "not_started" | "in_progress" | "at_risk" | "blocked" | "complete" | "archived";
export type MilestoneProgressMode = "manual" | "weighted";

export type Milestone = {
  id: string;
  workspace_id: string;
  project_id: string;
  parent_id: string | null;
  title: string;
  description: string | null;
  status: MilestoneStatus;
  due_at: string | null;
  progress_value: number;
  weight: number | null;
  progress_mode: MilestoneProgressMode;
  completed_at: string | null;
  depends_on: string[];
  version: number;
  updated_at: string;
};

export type ReviewDecision = "include" | "exclude" | "maybe";

export type ReviewItem = {
  id: string;
  workspace_id: string;
  review_id: string;
  stage_id: string;
  title: string;
  source_identifier: string | null;
  decision: ReviewDecision | null;
  reviewer: string | null;
  tags: string[];
  notes: string | null;
  external_url: string | null;
  version: number;
  updated_at: string;
};

export type ExperimentState = "draft" | "finalized";
export type ExperimentTemplate = "qpcr" | "primer_design";

export type Experiment = {
  id: string;
  workspace_id: string;
  project_id: string;
  template_type: ExperimentTemplate | null;
  title: string;
  occurred_at: string;
  objective: string | null;
  protocol: string | null;
  variables: string | null;
  materials: string | null;
  observations: string | null;
  deviations: string | null;
  result_summary: string | null;
  next_steps: string | null;
  state: ExperimentState;
  revision_number: number;
  version: number;
  updated_at: string;
};
