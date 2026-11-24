"use client";
import type { FormEvent } from "react";
import { useCallback, useEffect, useState } from "react";
import { apiRequest } from "@/lib/api/client";
import type { Project, Task, Workspace } from "@/lib/types/domain";
import { UndoBar } from "@/components/undo-bar";
import { humanize } from "@/lib/format";
import { OPEN_STATUSES, byNextUp, taskMeta } from "@/lib/tasks";

const PROJECT_STATUSES = ["planned", "in_progress", "on_hold", "complete"] as const;

export default function ProjectsPage() {
  const [workspace, setWorkspace] = useState<Workspace | null>(null);
  const [projects, setProjects] = useState<Project[]>([]);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [name, setName] = useState("");
  const [taskTitle, setTaskTitle] = useState("");
  const [taskProject, setTaskProject] = useState("");
  const [renaming, setRenaming] = useState<{ id: string; name: string } | null>(null);
  const [showDone, setShowDone] = useState(false);
  const [undo, setUndo] = useState<{ message: string; run: () => Promise<void> } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    try {
      const ws = (await apiRequest<Workspace[]>("/workspaces")).data[0] ?? null;
      setWorkspace(ws);
      if (!ws) return;
      const [p, t] = await Promise.all([
        apiRequest<Project[]>(`/projects?workspace_id=${ws.id}`),
        apiRequest<Task[]>(`/tasks?workspace_id=${ws.id}&limit=100`),
      ]);
      setProjects(p.data);
      setTasks(t.data);
    } catch {
      setError("Your projects could not be loaded. Check your connection and try again.");
    }
  }, []);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void load(); }, [load]);

  /** Runs one change, reloads, and reports a failure in the page. Resolves true on success. */
  async function act(work: () => Promise<unknown>, fallback: string) {
    setBusy(true);
    setError("");
    try {
      await work();
      await load();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : fallback);
      return false;
    } finally {
      setBusy(false);
    }
  }

  async function addProject(e: FormEvent) {
    e.preventDefault();
    if (!workspace || !name.trim()) return;
    if (await act(() => apiRequest("/projects", { method: "POST", body: { workspace_id: workspace.id, name: name.trim(), category: "personal", status: "in_progress", progress_mode: "manual", progress_value: 0 } }), "The project could not be added.")) setName("");
  }

  async function updateProject(project: Project, changes: Record<string, unknown>) {
    await act(() => apiRequest(`/projects/${project.id}`, { method: "PATCH", body: changes }), "The project could not be updated.");
  }

  async function rename(e: FormEvent) {
    e.preventDefault();
    if (!renaming?.name.trim()) return;
    const project = projects.find((p) => p.id === renaming.id);
    if (project) await updateProject(project, { name: renaming.name.trim() });
    setRenaming(null);
  }

  async function deleteProject(project: Project) {
    const linked = tasks.filter((t) => t.project_id === project.id && OPEN_STATUSES.has(t.status)).length;
    const extra = linked ? ` Its ${linked} open task${linked === 1 ? "" : "s"} stay in your task list.` : "";
    if (!window.confirm(`Delete the project “${project.name}”?${extra} This cannot be undone.`)) return;
    await act(() => apiRequest(`/projects/${project.id}`, { method: "DELETE" }), "The project could not be deleted.");
  }

  async function addTask(e: FormEvent) {
    e.preventDefault();
    if (!workspace || !taskTitle.trim()) return;
    if (await act(() => apiRequest("/tasks", { method: "POST", body: { workspace_id: workspace.id, project_id: taskProject || null, title: taskTitle.trim(), status: "inbox", priority: "normal" } }), "The task could not be added.")) setTaskTitle("");
  }

  async function setTaskStatus(task: Task, status: string) {
    return act(() => apiRequest(`/tasks/${task.id}`, { method: "PATCH", body: { status, completed_at: status === "complete" ? new Date().toISOString() : null } }), "The task could not be updated.");
  }

  async function complete(task: Task) {
    if (await setTaskStatus(task, "complete")) {
      setUndo({ message: `“${task.title}” marked done.`, run: async () => { await setTaskStatus(task, task.status); } });
    }
  }

  async function deleteTask(task: Task) {
    if (!workspace) return;
    if (await act(() => apiRequest(`/tasks/${task.id}`, { method: "DELETE" }), "The task could not be deleted.")) {
      // A deleted task cannot be revived, so undo adds it back as a new task with the same details.
      setUndo({
        message: `“${task.title}” deleted.`,
        run: async () => {
          await act(() => apiRequest("/tasks", { method: "POST", body: { workspace_id: workspace.id, project_id: task.project_id ?? null, title: task.title, description: task.description ?? null, status: task.status, priority: task.priority, due_at: task.due_at ?? null } }), "The task could not be restored.");
        },
      });
    }
  }

  async function runUndo() {
    if (!undo) return;
    await undo.run();
    setUndo(null);
  }

  const open = tasks.filter((t) => OPEN_STATUSES.has(t.status)).sort(byNextUp);
  const finished = tasks.filter((t) => t.status === "complete");
  const openFor = (id: string) => open.filter((t) => t.project_id === id).length;

  return (
    <div className="page-content">
      <div className="page-heading">
        <div>
          <p className="eyebrow">Planning space</p>
          <h1>Projects, with context.</h1>
          <p className="page-lede">Keep the work, the next action, and the wider question close together.</p>
        </div>
      </div>
      {error && <div className="notice notice-error" role="alert">{error}</div>}
      <div className="content-grid projects-grid">
        <section className="panel" aria-labelledby="projects-title">
          <div className="panel-heading">
            <div><p className="eyebrow">Active projects</p><h2 id="projects-title">{projects.length ? `${projects.length} in motion` : "Your first project"}</h2></div>
          </div>
          <div className="project-list">
            {projects.map((project) => {
              const progress = Number(project.progress_value ?? 0);
              const count = openFor(project.id);
              return (
                <article className="project-card" key={project.id}>
                  <div className="project-card-top"><span className="project-dot" aria-hidden="true" /><span className="status-badge">{humanize(project.status)}</span></div>
                  {renaming?.id === project.id ? (
                    <form className="project-rename" onSubmit={(e) => void rename(e)}>
                      <label className="sr-only" htmlFor={`rename-${project.id}`}>Project name</label>
                      <input id={`rename-${project.id}`} autoFocus required maxLength={120} value={renaming.name} onChange={(e) => setRenaming({ id: project.id, name: e.target.value })} onKeyDown={(e) => { if (e.key === "Escape") setRenaming(null); }} />
                      <button className="button button-primary" disabled={busy}>Save</button>
                      <button className="button button-secondary" type="button" onClick={() => setRenaming(null)}>Cancel</button>
                    </form>
                  ) : <h3>{project.name}</h3>}
                  <p>{project.description || (count ? `${count} open task${count === 1 ? "" : "s"}.` : "No open tasks. Add the next useful step.")}</p>
                  <div className="progress-track" role="img" aria-label={`${progress}% complete`}><span style={{ width: `${progress}%` }} /></div>
                  <small>{progress}% complete</small>
                  <div className="project-actions">
                    <label className="sr-only" htmlFor={`status-${project.id}`}>Status of {project.name}</label>
                    <select id={`status-${project.id}`} value={project.status} disabled={busy} onChange={(e) => void updateProject(project, { status: e.target.value, ...(e.target.value === "complete" ? { progress_value: 100 } : {}) })}>
                      {PROJECT_STATUSES.map((s) => <option key={s} value={s}>{humanize(s)}</option>)}
                      {!PROJECT_STATUSES.includes(project.status as (typeof PROJECT_STATUSES)[number]) && <option value={project.status}>{humanize(project.status)}</option>}
                    </select>
                    <button className="text-button" type="button" onClick={() => setRenaming({ id: project.id, name: project.name })} aria-label={`Rename ${project.name}`}>Rename</button>
                    <button className="text-button danger-text" type="button" onClick={() => void deleteProject(project)} disabled={busy} aria-label={`Delete ${project.name}`}>Delete</button>
                  </div>
                </article>
              );
            })}
            {!projects.length && <div className="empty-state"><h3>No projects yet.</h3><p>Name the work you want to keep moving.</p></div>}
          </div>
          <form className="inline-form" onSubmit={(e) => void addProject(e)}>
            <label className="sr-only" htmlFor="project-name">Project name</label>
            <input id="project-name" maxLength={120} placeholder="New project name" value={name} onChange={(e) => setName(e.target.value)} />
            <button className="button button-primary" disabled={busy || !name.trim()}>Add project</button>
          </form>
        </section>

        <section className="panel" aria-labelledby="tasks-title">
          <div className="panel-heading">
            <div><p className="eyebrow">Task inbox</p><h2 id="tasks-title">{open.length} next action{open.length === 1 ? "" : "s"}</h2></div>
          </div>
          <form className="inline-form" onSubmit={(e) => void addTask(e)}>
            <label className="sr-only" htmlFor="task-title">Task title</label>
            <input id="task-title" maxLength={240} placeholder="Add a next action" value={taskTitle} onChange={(e) => setTaskTitle(e.target.value)} />
            {projects.length > 0 && (
              <>
                <label className="sr-only" htmlFor="task-project">Project</label>
                <select id="task-project" value={taskProject} onChange={(e) => setTaskProject(e.target.value)}>
                  <option value="">No project</option>
                  {projects.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                </select>
              </>
            )}
            <button className="button button-secondary" disabled={busy || !taskTitle.trim()}>Add task</button>
          </form>
          {open.length ? (
            <ul className="task-list compact">
              {open.map((task) => (
                <li key={task.id}>
                  <button type="button" className="task-toggle" onClick={() => void complete(task)} disabled={busy} aria-label={`Mark “${task.title}” done`}><span className="task-check" aria-hidden="true" /></button>
                  <div><b>{task.title}</b><small>{taskMeta(task, projects)}</small></div>
                  <button type="button" className="time-block-delete" onClick={() => void deleteTask(task)} disabled={busy} aria-label={`Delete “${task.title}”`}>×</button>
                </li>
              ))}
            </ul>
          ) : <p className="inline-note">Nothing waiting. Add the next small step above.</p>}
          {finished.length > 0 && (
            <div className="done-tasks">
              <button type="button" className="text-button" aria-expanded={showDone} onClick={() => setShowDone((v) => !v)}>
                {showDone ? "Hide" : "Show"} {finished.length} completed
              </button>
              {showDone && (
                <ul className="task-list compact">
                  {finished.map((task) => (
                    <li key={task.id} className="task-done">
                      <button type="button" className="task-toggle" onClick={() => void setTaskStatus(task, "inbox")} disabled={busy} aria-label={`Reopen “${task.title}”`}><span className="task-check checked" aria-hidden="true">✓</span></button>
                      <div><b>{task.title}</b><small>{taskMeta(task, projects)}</small></div>
                      <button type="button" className="time-block-delete" onClick={() => void deleteTask(task)} disabled={busy} aria-label={`Delete “${task.title}”`}>×</button>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          )}
        </section>
      </div>
      {undo && <UndoBar message={undo.message} busy={busy} onUndo={() => void runUndo()} onDismiss={() => setUndo(null)} />}
    </div>
  );
}
