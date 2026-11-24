"use client";
import type { FormEvent } from "react";
import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from "react";
import { ApiClientError, apiRequest } from "@/lib/api/client";
import type { Project, Task, TimeBlock, Workspace } from "@/lib/types/domain";
import { UndoBar } from "@/components/undo-bar";
import { OPEN_STATUSES, byNextUp, taskMeta } from "@/lib/tasks";

const noSubscribe = () => () => {};
const greeting = () => {
  const hour = new Date().getHours();
  return hour < 12 ? "Good morning." : hour < 18 ? "Good afternoon." : "Good evening.";
};
const serverGreeting = () => "Today.";
const timeLabel = (iso: string) => new Date(iso).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });

export default function TodayPage() {
  const hello = useSyncExternalStore(noSubscribe, greeting, serverGreeting);
  const [workspace, setWorkspace] = useState<Workspace | null>(null);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [projects, setProjects] = useState<Project[]>([]);
  const [blocks, setBlocks] = useState<TimeBlock[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [title, setTitle] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<Task | null>(null);
  const input = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    try {
      const current = (await apiRequest<Workspace[]>("/workspaces")).data[0] ?? null;
      setWorkspace(current);
      if (!current) return;
      const start = new Date();
      start.setHours(0, 0, 0, 0);
      const end = new Date(start);
      end.setDate(start.getDate() + 1);
      const range = `start=${encodeURIComponent(start.toISOString())}&end=${encodeURIComponent(end.toISOString())}`;
      const [taskResult, projectResult, blockResult] = await Promise.all([
        apiRequest<Task[]>(`/tasks?workspace_id=${current.id}&limit=100`),
        apiRequest<Project[]>(`/projects?workspace_id=${current.id}`),
        apiRequest<TimeBlock[]>(`/time-blocks?workspace_id=${current.id}&${range}`),
      ]);
      setTasks(taskResult.data);
      setProjects(projectResult.data);
      setBlocks(blockResult.data.sort((a, b) => a.starts_at.localeCompare(b.starts_at)));
      setError("");
    } catch (caught) {
      setError(caught instanceof ApiClientError ? caught.message : "Your workspace could not be loaded. Check your connection and try again.");
    } finally {
      setLoading(false);
    }
  }, []);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void load(); }, [load]);

  const open = tasks.filter((t) => OPEN_STATUSES.has(t.status)).sort(byNextUp);

  async function addTask(event: FormEvent) {
    event.preventDefault();
    if (!workspace || !title.trim()) return;
    setBusy(true);
    setError("");
    try {
      await apiRequest("/tasks", { method: "POST", body: { workspace_id: workspace.id, title: title.trim(), status: "inbox", priority: "normal" } });
      setTitle("");
      await load();
      input.current?.focus();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "The task could not be added.");
    } finally {
      setBusy(false);
    }
  }

  async function setStatus(task: Task, status: string) {
    setBusy(true);
    setError("");
    try {
      await apiRequest(`/tasks/${task.id}`, {
        method: "PATCH",
        body: { status, completed_at: status === "complete" ? new Date().toISOString() : null },
      });
      await load();
      return true;
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "The task could not be updated.");
      return false;
    } finally {
      setBusy(false);
    }
  }

  async function complete(task: Task) {
    if (await setStatus(task, "complete")) setDone(task);
  }

  async function undoComplete() {
    if (!done) return;
    if (await setStatus(done, done.status)) setDone(null);
  }

  return (
    <div className="page-content">
      <div className="page-heading">
        <div>
          <p className="eyebrow">Today · Focused work</p>
          <h1>{hello}</h1>
          <p className="page-lede">Here is a small, useful view of what deserves your attention today.</p>
        </div>
        <button className="button button-primary" type="button" onClick={() => input.current?.focus()} disabled={!workspace}>＋ Add task</button>
      </div>
      {error && <div className="notice notice-error" role="alert">{error}</div>}
      {loading ? <div className="loading-card" role="status">Loading your workspace…</div> : (
        <>
          <section className="metric-grid" aria-label="Today at a glance">
            <article className="metric-card"><span className="metric-label">Open tasks</span><strong>{open.length}</strong><small>Keep the list kind and clear.</small></article>
            <article className="metric-card metric-card-accent"><span className="metric-label">Time blocks today</span><strong>{blocks.length}</strong><small>Protected time for focused work.</small></article>
            <article className="metric-card"><span className="metric-label">Workspace</span><strong>{workspace ? "Ready" : "Start"}</strong><small>{workspace?.name ?? "Create your first workspace."}</small></article>
          </section>
          <div className="content-grid">
            <section className="panel" aria-labelledby="next-action">
              <div className="panel-heading">
                <div><p className="eyebrow">Next actions</p><h2 id="next-action">Move one thing forward.</h2></div>
                <a className="text-link" href="/app/projects">See projects →</a>
              </div>
              <form className="inline-form task-add" onSubmit={(e) => void addTask(e)}>
                <label className="sr-only" htmlFor="today-task">New task</label>
                <input id="today-task" ref={input} maxLength={240} placeholder="Add a next action" value={title} onChange={(e) => setTitle(e.target.value)} disabled={!workspace} />
                <button className="button button-secondary" disabled={busy || !title.trim()}>Add task</button>
              </form>
              {open.length ? (
                <ul className="task-list">
                  {open.slice(0, 12).map((task) => (
                    <li key={task.id}>
                      <button type="button" className="task-toggle" onClick={() => void complete(task)} disabled={busy} aria-label={`Mark “${task.title}” done`}><span className="task-check" aria-hidden="true" /></button>
                      <div><b>{task.title}</b><small>{taskMeta(task, projects)}</small></div>
                    </li>
                  ))}
                </ul>
              ) : (
                <div className="empty-state"><span className="empty-icon" aria-hidden="true">○</span><h3>No open tasks yet.</h3><p>Start with the smallest visible step. Type it above and press Add task.</p></div>
              )}
              {open.length > 12 && <p className="inline-note">{open.length - 12} more on the <a className="text-link" href="/app/projects">Projects page</a>.</p>}
            </section>
            <aside className="panel panel-tinted" aria-labelledby="today-schedule">
              <p className="eyebrow">Today&rsquo;s schedule</p>
              <h2 id="today-schedule">{blocks.length ? "Time you have protected." : "Nothing scheduled yet."}</h2>
              {blocks.length ? (
                <ul className="today-blocks">
                  {blocks.map((b) => <li key={b.id}><span>{timeLabel(b.starts_at)}–{timeLabel(b.ends_at)}</span><b>{b.title}</b></li>)}
                </ul>
              ) : <p>Choose one action that reduces uncertainty for future you, and give it a time block.</p>}
              <a className="text-link" href="/app/calendar">Open calendar →</a>
            </aside>
          </div>
        </>
      )}
      {done && <UndoBar message={`“${done.title}” marked done.`} busy={busy} onUndo={() => void undoComplete()} onDismiss={() => setDone(null)} />}
    </div>
  );
}
