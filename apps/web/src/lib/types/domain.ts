export type Workspace = { id: string; name: string; owner_id?: string };
export type Project = { id: string; workspace_id: string; name: string; category: string; status: string; description?: string | null; progress_value?: number | string | null; target_at?: string | null };
export type Task = { id: string; workspace_id: string; project_id?: string | null; title: string; description?: string | null; status: string; priority: string; due_at?: string | null; estimated_minutes?: number | null; tags?: string[] };
export type TimeBlock = { id: string; title: string; category: string; starts_at: string; ends_at: string; status: string; task_id?: string | null };
export type Milestone = { id: string; workspace_id: string; project_id: string; title: string; status: string; due_at?: string | null; progress_value?: number | string | null; description?: string | null };
export type Session = { access_token: string; refresh_token: string; expires_in: number; display_name?: string; email?: string };
