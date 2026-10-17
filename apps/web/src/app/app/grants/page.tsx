"use client";

import type { FormEvent } from "react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { apiRequest } from "@/lib/api/client";
import type { Project, Workspace } from "@/lib/types/domain";

type FundingStatus =
  | "not_started"
  | "researching"
  | "preparing"
  | "submitted"
  | "awarded"
  | "rejected"
  | "not_eligible";
type FundingPriority = "high" | "medium" | "low";
type Opportunity = {
  id: string;
  workspace_id: string;
  project_id: string | null;
  category: string;
  title: string;
  organisation: string;
  amount: string | null;
  opens_label: string | null;
  deadline_at: string | null;
  deadline_type: string;
  eligibility_notes: string | null;
  priority: FundingPriority;
  status: FundingStatus;
  date_applied: string | null;
  next_action: string | null;
  official_link: string | null;
  other_source: string | null;
  version: number;
  updated_at: string;
};
type GrantForm = {
  project_id: string;
  category: string;
  title: string;
  organisation: string;
  amount: string;
  opens_label: string;
  deadline: string;
  deadline_type: string;
  eligibility_notes: string;
  priority: FundingPriority;
  status: FundingStatus;
  date_applied: string;
  next_action: string;
  official_link: string;
  other_source: string;
};

const statuses: FundingStatus[] = [
  "not_started", "researching", "preparing", "submitted", "awarded", "rejected", "not_eligible",
];
const priorities: FundingPriority[] = ["high", "medium", "low"];
const blankForm = (): GrantForm => ({
  project_id: "", category: "Project funding", title: "", organisation: "", amount: "",
  opens_label: "", deadline: "", deadline_type: "Not announced", eligibility_notes: "",
  priority: "medium", status: "not_started", date_applied: "", next_action: "",
  official_link: "", other_source: "",
});
const newId = () => crypto.randomUUID();
const label = (value: string) => value.replaceAll("_", " ").replace(/\b\w/g, (c) => c.toUpperCase());
const dateValue = (value: string | null) => value ? value.slice(0, 10) : "";
const dateLabel = (value: string | null) => value
  ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeZone: "UTC" }).format(new Date(value))
  : "Not set";

function formFromOpportunity(item: Opportunity): GrantForm {
  return {
    project_id: item.project_id ?? "", category: item.category, title: item.title,
    organisation: item.organisation, amount: item.amount ?? "", opens_label: item.opens_label ?? "",
    deadline: dateValue(item.deadline_at), deadline_type: item.deadline_type,
    eligibility_notes: item.eligibility_notes ?? "", priority: item.priority, status: item.status,
    date_applied: dateValue(item.date_applied), next_action: item.next_action ?? "",
    official_link: item.official_link ?? "", other_source: item.other_source ?? "",
  };
}

export default function GrantsPage() {
  const [workspace, setWorkspace] = useState<Workspace | null>(null);
  const [projects, setProjects] = useState<Project[]>([]);
  const [opportunities, setOpportunities] = useState<Opportunity[]>([]);
  const [form, setForm] = useState<GrantForm>(blankForm);
  const [editing, setEditing] = useState<Opportunity | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const ws = (await apiRequest<Workspace[]>("/workspaces")).data[0] ?? null;
      setWorkspace(ws);
      if (!ws) {
        setProjects([]);
        setOpportunities([]);
        return;
      }
      const [projectResponse, firstPage] = await Promise.all([
        apiRequest<Project[]>(`/projects?workspace_id=${ws.id}&view=all&limit=100`),
        apiRequest<Opportunity[]>(`/funding-opportunities?workspace_id=${ws.id}&limit=100&offset=0`),
      ]);
      const all = [...firstPage.data];
      for (let offset = all.length; all.length > 0 && all.length % 100 === 0; offset += 100) {
        const next = await apiRequest<Opportunity[]>(
          `/funding-opportunities?workspace_id=${ws.id}&limit=100&offset=${offset}`,
        );
        all.push(...next.data);
        if (next.data.length < 100) break;
      }
      setProjects(projectResponse.data);
      setOpportunities(all);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not load grant opportunities. Please retry.");
    } finally {
      setLoading(false);
    }
  }, []);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void load(); }, [load]);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return opportunities.filter((item) => {
      const matchesQuery = !q || [item.title, item.organisation, item.category]
        .some((value) => value.toLowerCase().includes(q));
      return matchesQuery && (!statusFilter || item.status === statusFilter);
    });
  }, [opportunities, query, statusFilter]);

  function startNew() {
    setEditing(null);
    setForm(blankForm());
    setShowForm(true);
    setError("");
    setNotice("");
  }

  function startEdit(item: Opportunity) {
    setEditing(item);
    setForm(formFromOpportunity(item));
    setShowForm(true);
    setError("");
    setNotice("");
  }

  function closeForm() {
    setShowForm(false);
    setEditing(null);
    setForm(blankForm());
  }

  function update<K extends keyof GrantForm>(key: K, value: GrantForm[K]) {
    setForm((current) => ({ ...current, [key]: value }));
  }

  async function mutate(
    itemId: string,
    operation: "create" | "update" | "delete",
    changes: Record<string, unknown>,
    baseVersion?: number,
  ) {
    if (!workspace) throw new Error("No workspace is available for grant tracking.");
    const response = await apiRequest<{
      results: { status: string; message?: string; error_code?: string }[];
    }>("/sync/push", {
      method: "POST",
      body: {
        device_id: newId(),
        protocol_version: 1,
        cursor: 0,
        mutations: [{
          mutation_id: newId(),
          workspace_id: workspace.id,
          entity_type: "funding_opportunity",
          entity_id: itemId,
          operation,
          base_version: baseVersion,
          changes,
        }],
      },
    });
    const result = response.data.results[0];
    if (result?.status !== "accepted") {
      throw new Error(result?.message ?? `The grant change was rejected (${result?.error_code ?? "unknown error"}).`);
    }
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!workspace) return;
    setSaving(true);
    setError("");
    setNotice("");
    const changes = {
      project_id: form.project_id || null,
      category: form.category.trim(),
      title: form.title.trim(),
      organisation: form.organisation.trim(),
      amount: form.amount.trim() || null,
      opens_label: form.opens_label.trim() || null,
      deadline_at: form.deadline ? `${form.deadline}T00:00:00Z` : null,
      deadline_type: form.deadline_type,
      eligibility_notes: form.eligibility_notes.trim() || null,
      priority: form.priority,
      status: form.status,
      date_applied: form.date_applied ? `${form.date_applied}T00:00:00Z` : null,
      next_action: form.next_action.trim() || null,
      official_link: form.official_link.trim() || null,
      other_source: form.other_source.trim() || null,
    };
    try {
      await mutate(editing?.id ?? newId(), editing ? "update" : "create", changes, editing?.version);
      closeForm();
      await load();
      setNotice(editing ? "Grant opportunity updated." : "Grant opportunity added.");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not save the grant opportunity.");
    } finally {
      setSaving(false);
    }
  }

  async function remove(item: Opportunity) {
    if (!window.confirm(`Delete “${item.title}” from grant tracking?`)) return;
    setSaving(true);
    setError("");
    setNotice("");
    try {
      await mutate(item.id, "delete", {}, item.version);
      await load();
      setNotice("Grant opportunity deleted.");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not delete the grant opportunity.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="page-content grants-page">
      <div className="page-heading">
        <div>
          <p className="eyebrow">Funding workspace</p>
          <h1>Grant tracking</h1>
          <p className="page-lede">Keep opportunities, deadlines, eligibility notes, and next steps together.</p>
        </div>
        <button className="button button-primary" type="button" onClick={startNew} disabled={!workspace}>
          Add opportunity
        </button>
      </div>

      {error && <div className="notice notice-error" role="alert">{error}</div>}
      {notice && <div className="notice" role="status">{notice}</div>}

      {showForm && (
        <section className="panel grant-form-panel" aria-labelledby="grant-form-title">
          <div className="panel-heading">
            <div>
              <p className="eyebrow">Opportunity details</p>
              <h2 id="grant-form-title">{editing ? "Edit opportunity" : "New opportunity"}</h2>
            </div>
            <button className="button button-secondary" type="button" onClick={closeForm}>Cancel</button>
          </div>
          <form className="grant-form" onSubmit={save}>
            <div className="grant-form-grid">
              <label>Opportunity title<input required maxLength={240} value={form.title} onChange={(e) => update("title", e.target.value)} /></label>
              <label>Funding organisation<input required maxLength={240} value={form.organisation} onChange={(e) => update("organisation", e.target.value)} /></label>
              <label>Category<input required maxLength={120} value={form.category} onChange={(e) => update("category", e.target.value)} /></label>
              <label>Amount / support<input maxLength={500} value={form.amount} onChange={(e) => update("amount", e.target.value)} placeholder="e.g. Up to $10,000" /></label>
              <label>Linked project<select value={form.project_id} onChange={(e) => update("project_id", e.target.value)}><option value="">No project linked</option>{projects.map((project) => <option key={project.id} value={project.id}>{project.name}</option>)}</select></label>
              <label>Application status<select value={form.status} onChange={(e) => update("status", e.target.value as FundingStatus)}>{statuses.map((status) => <option key={status} value={status}>{label(status)}</option>)}</select></label>
              <label>Priority<select value={form.priority} onChange={(e) => update("priority", e.target.value as FundingPriority)}>{priorities.map((priority) => <option key={priority} value={priority}>{label(priority)}</option>)}</select></label>
              <label>Deadline type<select value={form.deadline_type} onChange={(e) => update("deadline_type", e.target.value)}>{["Confirmed", "Projected", "Not announced", "Closed"].map((value) => <option key={value}>{value}</option>)}</select></label>
              <label>Deadline<input type="date" value={form.deadline} onChange={(e) => update("deadline", e.target.value)} /></label>
              <label>Application date<input type="date" value={form.date_applied} onChange={(e) => update("date_applied", e.target.value)} /></label>
              <label>Opening information<input maxLength={120} value={form.opens_label} onChange={(e) => update("opens_label", e.target.value)} placeholder="e.g. Call opens in September" /></label>
              <label>Next action<input maxLength={2000} value={form.next_action} onChange={(e) => update("next_action", e.target.value)} placeholder="What needs to happen next?" /></label>
              <label>Official link<input type="url" value={form.official_link} onChange={(e) => update("official_link", e.target.value)} placeholder="https://…" /></label>
              <label>Other source<input maxLength={500} value={form.other_source} onChange={(e) => update("other_source", e.target.value)} placeholder="Where you found this opportunity" /></label>
            </div>
            <label>Eligibility notes<textarea maxLength={20000} rows={4} value={form.eligibility_notes} onChange={(e) => update("eligibility_notes", e.target.value)} /></label>
            <div className="grant-form-actions">
              <button className="button button-primary" type="submit" disabled={saving}>{saving ? "Saving…" : editing ? "Save changes" : "Add opportunity"}</button>
              <button className="button button-secondary" type="button" onClick={closeForm} disabled={saving}>Cancel</button>
            </div>
          </form>
        </section>
      )}

      <section className="panel grants-panel" aria-labelledby="grants-list-title">
        <div className="panel-heading grants-toolbar">
          <div>
            <p className="eyebrow">Your workspace</p>
            <h2 id="grants-list-title">{opportunities.length} tracked {opportunities.length === 1 ? "opportunity" : "opportunities"}</h2>
          </div>
          <div className="grant-filters">
            <label>Search<input type="search" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Title, organisation, category" /></label>
            <label>Status<select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}><option value="">All statuses</option>{statuses.map((status) => <option key={status} value={status}>{label(status)}</option>)}</select></label>
          </div>
        </div>

        {loading ? <p className="grant-empty">Loading grant opportunities…</p> : visible.length ? (
          <div className="grant-list">
            {visible.map((item) => (
              <article className="grant-card" key={item.id}>
                <div className="grant-card-heading">
                  <div><p className="eyebrow">{item.category}</p><h3>{item.title}</h3><p className="grant-organisation">{item.organisation}</p></div>
                  <span className="status-badge">{label(item.status)}</span>
                </div>
                <div className="grant-facts">
                  <span><b>Deadline</b>{dateLabel(item.deadline_at)}{item.deadline_type !== "Confirmed" && item.deadline_at ? ` · ${item.deadline_type.toLowerCase()}` : ""}</span>
                  <span><b>Priority</b>{label(item.priority)}</span>
                  {item.amount && <span><b>Support</b>{item.amount}</span>}
                  {item.next_action && <span><b>Next action</b>{item.next_action}</span>}
                </div>
                {item.eligibility_notes && <p className="grant-notes">{item.eligibility_notes}</p>}
                {item.official_link && <a className="grant-source" href={item.official_link} target="_blank" rel="noreferrer">Open official opportunity page</a>}
                <div className="grant-card-actions">
                  <button className="button button-secondary" type="button" onClick={() => startEdit(item)}>Edit</button>
                  <button className="button button-danger" type="button" onClick={() => void remove(item)} disabled={saving}>Delete</button>
                </div>
              </article>
            ))}
          </div>
        ) : (
          <div className="grant-empty"><h3>{opportunities.length ? "No matching opportunities." : "No grants tracked yet."}</h3><p>{opportunities.length ? "Change the search or status filter." : "Add a funding opportunity to start tracking deadlines, eligibility, and next actions."}</p></div>
        )}
      </section>
    </div>
  );
}
