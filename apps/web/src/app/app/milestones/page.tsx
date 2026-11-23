"use client";
import type { FormEvent } from "react";
import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { apiRequest } from "@/lib/api/client";
import type { Milestone, Project, Workspace } from "@/lib/types/domain";
import { useFormFocus } from "@/lib/use-form-focus";

const STATUSES = ["not_started", "in_progress", "at_risk", "blocked", "complete"] as const;
type Status = (typeof STATUSES)[number];
const label = (value: string) => value.replaceAll("_", " ").replace(/^\w/, (c) => c.toUpperCase());
const dueLabel = (value: string | null | undefined) => value
  ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeZone: "UTC" }).format(new Date(value))
  : null;

type MilestoneForm = { project_id: string; title: string; description: string; due: string; status: Status; progress: string };

export default function MilestonesPage() {
  const [workspace, setWorkspace] = useState<Workspace | null>(null);
  const [projects, setProjects] = useState<Project[]>([]);
  const [milestones, setMilestones] = useState<Milestone[]>([]);
  const [form, setForm] = useState<MilestoneForm | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const formRef = useFormFocus<HTMLElement>(form ? "new" : null);

  const load = useCallback(async () => {
    try {
      const ws = (await apiRequest<Workspace[]>("/workspaces")).data[0] ?? null;
      setWorkspace(ws);
      if (!ws) return;
      const [projectResponse, milestoneResponse] = await Promise.all([
        apiRequest<Project[]>(`/projects?workspace_id=${ws.id}&view=all&limit=100`),
        apiRequest<Milestone[]>(`/milestones?workspace_id=${ws.id}`),
      ]);
      setProjects(projectResponse.data);
      setMilestones(milestoneResponse.data);
    } catch {
      setError("Milestones are not available yet.");
    }
  }, []);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void load(); }, [load]);

  function openForm() {
    setForm({ project_id: projects[0]?.id ?? "", title: "", description: "", due: "", status: "not_started", progress: "0" });
    setError("");
    setNotice("");
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!form || !workspace) return;
    const progress = Math.min(100, Math.max(0, Number(form.progress) || 0));
    setSaving(true);
    setError("");
    try {
      const response = await apiRequest<{ results: { status: string; message?: string }[] }>("/sync/push", {
        method: "POST",
        body: {
          device_id: crypto.randomUUID(),
          protocol_version: 1,
          cursor: 0,
          mutations: [{
            mutation_id: crypto.randomUUID(),
            workspace_id: workspace.id,
            entity_type: "milestone",
            entity_id: crypto.randomUUID(),
            operation: "create",
            changes: {
              project_id: form.project_id,
              title: form.title.trim(),
              description: form.description.trim() || null,
              status: form.status,
              due_at: form.due ? `${form.due}T00:00:00Z` : null,
              progress_value: progress,
              progress_mode: "manual",
            },
          }],
        },
      });
      const result = response.data.results[0];
      if (result?.status !== "accepted") throw new Error(result?.message ?? "The milestone was not saved.");
      setForm(null);
      await load();
      setNotice("Milestone added.");
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
        <button className="button button-primary" type="button" onClick={openForm} disabled={!workspace}>＋ Add milestone</button>
      </div>
      {error && <div className="notice notice-error" role="alert">{error}</div>}
      {notice && <div className="notice" role="status">{notice}</div>}

      {form && (
        <section ref={formRef} className="panel grant-form-panel" aria-labelledby="milestone-form-title">
          <div className="panel-heading">
            <div><p className="eyebrow">Milestone</p><h2 id="milestone-form-title">New milestone</h2></div>
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
                <button className="button button-primary" type="submit" disabled={saving}>{saving ? "Saving…" : "Add milestone"}</button>
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
    </div>
  );
}
