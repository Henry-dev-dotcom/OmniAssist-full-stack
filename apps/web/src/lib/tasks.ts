import type { Project, Task } from "@/lib/types/domain";
import { humanize } from "@/lib/format";

/** Task statuses that still need doing. The API's values, not labels. */
export const OPEN_STATUSES = new Set(["inbox", "planned", "in_progress"]);

const PRIORITY_RANK: Record<string, number> = { critical: 0, high: 1, normal: 2, low: 3 };

/** Due date first (soonest, undated last), then priority, then title. */
export function byNextUp(a: Task, b: Task) {
  const due = (t: Task) => (t.due_at ? new Date(t.due_at).getTime() : Number.POSITIVE_INFINITY);
  return due(a) - due(b)
    || (PRIORITY_RANK[a.priority] ?? 9) - (PRIORITY_RANK[b.priority] ?? 9)
    || a.title.localeCompare(b.title);
}

/** "Thesis · High priority · due 3 Dec" — only the parts that say something. */
export function taskMeta(task: Task, projects: Project[]) {
  const project = projects.find((p) => p.id === task.project_id)?.name;
  return [
    project,
    task.status === "in_progress" ? "In progress" : null,
    task.priority !== "normal" ? `${humanize(task.priority)} priority` : null,
    task.due_at ? `due ${new Date(task.due_at).toLocaleDateString(undefined, { day: "numeric", month: "short" })}` : null,
  ].filter(Boolean).join(" · ") || "Inbox";
}
