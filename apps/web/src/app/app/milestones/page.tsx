"use client";
import type { FormEvent } from "react";
import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { apiRequest } from "@/lib/api/client";
import type { Milestone, Project, Workspace } from "@/lib/types/domain";
import { useFormFocus } from "@/lib/use-form-focus";
import { ReminderPicker } from "@/components/reminder-picker";
import { UndoBar } from "@/components/undo-bar";
import { DEADLINE_CHOICES, useReminders } from "@/lib/reminders";

const STATUSES = ["not_started", "in_progress", "at_risk", "blocked", "complete"] as const;
type Status = (typeof STATUSES)[number];
const label = (value: string) => value.replaceAll("_", " ").replace(/^\w/, (c) => c.toUpperCase());
const dueLabel = (value: string | null | undefined) => value
  ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeZone: "UTC" }).format(new Date(value))
  : null;

type Row = Milestone & { version?: number };
type MilestoneForm = { project_id: string; title: string; description: string; due: string; status: Status; progress: string; editing: Row | null };
type PushResult = { results: { status: string; message?: string }[] };

export default function MilestonesPage() {
  const [workspace, setWorkspace] = useState<Workspace | null>(null);
  const [projects, setProjects] = useState<Project[]>([]);
  const [milestones, setMilestones] = useState<Row[]>([]);
  const [deleted, setDeleted] = useState<Row | null>(null);
  const [form, setForm] = useState<MilestoneForm | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const formRef = useFormFocus<HTMLElement>(form ? form.editing?.id ?? "new" : null);
  const reminders = useReminders(workspace?.id);

  const load = useCallback(async () => {
    try {
      const ws = (await apiRequest<Workspace[]>("/workspaces")).data[0] ?? null;
      setWorkspace(ws);
      if (!ws) return;
      const [projectResponse, milestoneResponse] = await Promise.all([
        apiRequest<Project[]>(`/projects?workspace_id=${ws.id}&view=all&limit=100`),
        apiRequest<Row[]>(`/milestones?workspace_id=${ws.id}`),
      ]);
      setProjects(projectResponse.data);
      setMilestones(milestoneResponse.data);
    } catch {
      setError("Milestones are not available yet.");
    }
  }, []);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void load(); }, [load]);

  function openForm(editing: Row | null = null) {
    setForm(editing
      ? {
        project_id: editing.project_id, title: editing.title, description: editing.description ?? "",
        due: editing.due_at ? editing.due_at.slice(0, 10) : "",
        status: (STATUSES as readonly string[]).includes(editing.status) ? editing.status as Status : "not_started",
        progress: String(Number(editing.progress_value ?? 0)), editing,
      }
      : { project_id: projects[0]?.id ?? "", title: "", description: "", due: "", status: "not_started", progress: "0", editing: null });
    setError("");
    setNotice("");
  }

  /** One sync mutation for a milestone; throws with the server's reason when it is rejected. */
  async function push(operation: "create" | "update" | "delete", id: string, changes: Record<string, unknown>, baseVersion?: number) {
    if (!workspace) throw new Error("No workspace is available.");
    const response = await apiRequest<PushResult>("/sync/push", {
      method: "POST",
      body: {
        device_id: crypto.randomUUID(), protocol_version: 1, cursor: 0,
        mutations: [{ mutation_id: crypto.randomUUID(), workspace_id: workspace.id, entity_type: "milestone", entity_id: id, operation, base_version: baseVersion, changes }],
      },
    });
    const result = response.data.results[0];
    if (result?.status !== "accepted") throw new Error(result?.message ?? "The milestone was not saved.");
  }

  async function quick(work: () => Promise<void>, message: string) {
    setSaving(true);
    setError("");
    setNotice("");
    try {
      await work();
      await load();
      if (message) setNotice(message);
      return true;
    } catch (e) {
      setError(e instanceof Error ? e.message : "The milestone could not be updated.");
      return false;
    } finally {
      setSaving(false);
    }
  }

  const fields = (m: Row) => ({
    project_id: m.project_id, title: m.title, description: m.description ?? null, status: m.status,
    due_at: m.due_at ?? null, progress_value: Number(m.progress_value ?? 0), progress_mode: "manual",
  });

  function toggleDone(m: Row) {
    const done = m.status !== "complete";
    void quick(
      () => push("update", m.id, done ? { status: "complete", progress_value: 100 } : { status: "in_progress" }, m.version),
      done ? `“${m.title}” marked complete.` : `“${m.title}” reopened.`,
    );
  }

  async function remove(m: Row) {
    if (await quick(() => push("delete", m.id, {}, m.version), "")) setDeleted(m);
  }

  async function restore() {
    if (!deleted) return;
    // A deleted milestone cannot be revived, so it comes back as a new one with the same details.
    if (await quick(() => push("create", crypto.randomUUID(), fields(deleted)), `“${deleted.title}” restored.`)) setDeleted(null);
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!form || !workspace) return;
    const progress = Math.min(100, Math.max(0, Number(form.progress) || 0));
    setSaving(true);
    setError("");
    try {
      const changes = {
        project_id: form.project_id,
        title: form.title.trim(),
        description: form.description.trim() || null,
        status: form.status,
        due_at: form.due ? `${form.due}T00:00:00Z` : null,
        progress_value: form.status === "complete" ? 100 : progress,
        progress_mode: "manual",
      };
      const edited = form.editing;
      if (edited) await push("update", edited.id, changes, edited.version);
      else await push("create", crypto.randomUUID(), changes);
      setForm(null);
      await load();
      setNotice(edited ? "Milestone updated." : "Milestone added.");
    } catch (e) {
      setError(e instanceof Error ? e.message : "The milestone could not be saved.");
    } finally {
      setSaving(false);
    }
  }

  const set = (key: keyof MilestoneForm) => (e: { target: { value: string } }) =>
    setForm((current) => (current ? { ...current, [key]: e.target.value } : current));
  const projectName = (id: string) => projects.find((p) => p.id === id)?.name;

  return (
    <div className="page-content">
      <div className="page-heading">
        <div>
          <p className="eyebrow">The long arc</p>
          <h1>Milestones make progress visible.</h1>
          <p className="page-lede">Turn a large goal into a sequence you can return to.</p>
        </div>
        <button className="button button-primary" type="button" onClick={() => openForm()} disabled={!workspace}>＋ Add milestone</button>
      </div>
      {error && <div className="notice notice-error" role="alert">{error}</div>}
      {notice && <div className="notice" role="status">{notice}</div>}

      {form && (
        <section ref={formRef} className="panel grant-form-panel" aria-labelledby="milestone-form-title">
          <div className="panel-heading">
            <div><p className="eyebrow">Milestone</p><h2 id="milestone-form-title">{form.editing ? "Edit milestone" : "New milestone"}</h2></div>
            <button className="button button-secondary" type="button" onClick={() => setForm(null)}>Cancel</button>
          </div>
          {projects.length === 0 ? (
            <div className="empty-state">
              <h3>Create a project first.</h3>
              <p>Every milestone belongs to a project, such as your MPhil or a scholarship application.</p>
              <Link className="button button-primary button-link" href="/app/projects">Go to Projects</Link>
            </div>
          ) : (
            <form className="grant-form" onSubmit={(e) => void save(e)}>
              <div className="grant-form-grid">
                <label>Milestone<input required maxLength={240} value={form.title} onChange={set("title")} placeholder="e.g. Submit MIPT application" /></label>
                <label>Project<select required value={form.project_id} onChange={set("project_id")}>{projects.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select></label>
                <label>Due date<input type="date" value={form.due} onChange={set("due")} /></label>
                <label>Status<select value={form.status} onChange={set("status")}>{STATUSES.map((s) => <option key={s} value={s}>{label(s)}</option>)}</select></label>
                <label>Progress (%)<input type="number" inputMode="numeric" min={0} max={100} step={5} value={form.progress} onChange={set("progress")} /></label>
              </div>
              <label>Notes<textarea maxLength={20000} rows={3} value={form.description} onChange={set("description")} placeholder="What does done look like?" /></label>
              <div className="grant-form-actions">
                <button className="button button-primary" type="submit" disabled={saving}>{saving ? "Saving…" : form.editing ? "Save changes" : "Add milestone"}</button>
                <button className="button button-secondary" type="button" onClick={() => setForm(null)} disabled={saving}>Cancel</button>
              </div>
            </form>
          )}
        </section>
      )}

      <section className="panel">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">Project checkpoints</p>
            <h2>{milestones.length ? "Where the work stands" : "Start with the shape of the work."}</h2>
          </div>
        </div>
        {milestones.length ? (
          <div className="milestone-list">
            {milestones.map((milestone) => {
              const progress = Number(milestone.progress_value ?? 0);
              const due = dueLabel(milestone.due_at);
              const project = projectName(milestone.project_id);
              return (
                <article className="milestone-row" key={milestone.id} data-status={milestone.status}>
                  <span className="milestone-status" aria-hidden="true" />
                  <div>
                    <h3>{milestone.title}</h3>
                    <p className="milestone-meta">{[project, label(milestone.status), due && `Due ${due}`].filter(Boolean).join(" · ")}</p>
                    <p>{milestone.description || "A meaningful checkpoint in the work."}</p>
                    {milestone.due_at && milestone.status !== "complete" && milestone.status !== "archived" && (
                      <ReminderPicker
                        label={`Reminder for ${milestone.title}`}
                        choices={DEADLINE_CHOICES}
                        current={reminders.offsetsFor("milestone", milestone.id)}
                        onChange={async (offsets) => (await reminders.setReminders("milestone", milestone.id, offsets))
                          ? "That time has already passed, so no reminder was set." : ""}
                      />
                    )}
                    <div className="milestone-actions">
                      <button type="button" className="text-button" onClick={() => toggleDone(milestone)} disabled={saving} aria-label={`${milestone.status === "complete" ? "Reopen" : "Mark complete"}: ${milestone.title}`}>{milestone.status === "complete" ? "Reopen" : "Mark complete"}</button>
                      <button type="button" className="text-button" onClick={() => openForm(milestone)} aria-label={`Edit ${milestone.title}`}>Edit</button>
                      <button type="button" className="text-button danger-text" onClick={() => void remove(milestone)} disabled={saving} aria-label={`Delete ${milestone.title}`}>Delete</button>
                    </div>
                  </div>
                  <div className="milestone-progress">
                    <b>{progress}%</b>
                    <div className="progress-track" role="img" aria-label={`${progress}% complete`}><span style={{ width: `${progress}%` }} /></div>
                  </div>
                </article>
              );
            })}
          </div>
        ) : (
          <div className="empty-state wide">
            <span className="empty-icon" aria-hidden="true">◇</span>
            <h3>No milestones yet.</h3>
            <p>Milestones are not deadlines in disguise. They are visible places to pause, notice what changed, and choose what comes next.</p>
          </div>
        )}
      </section>
      {deleted && <UndoBar message={`“${deleted.title}” deleted.`} busy={saving} onUndo={() => void restore()} onDismiss={() => setDeleted(null)} />}
    </div>
  );
}
