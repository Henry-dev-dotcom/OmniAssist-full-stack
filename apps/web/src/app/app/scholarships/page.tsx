"use client";

import type { ChangeEvent, FormEvent } from "react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { apiRequest } from "@/lib/api/client";
import type { Workspace } from "@/lib/types/domain";
import { STARTER_APPLICATIONS } from "@/lib/scholarships/starter";
import { listScholarships, pushChanges } from "@/lib/scholarships/api";
import { scholarshipsFromCsv, scholarshipsToCsv } from "@/lib/scholarships/csv";
import {
  CHECKLIST, CLOSED, REGION_SUGGESTIONS, STATUSES, STEPS, blankDraft, checklistProgress, daysUntil,
  draftFromScholarship, label, toChanges,
  type Scholarship, type ScholarshipDraft, type ScholarshipStatus,
} from "@/lib/scholarships/types";

const dateLabel = (value: string | null) => value
  ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeZone: "UTC" }).format(new Date(value))
  : "No date set";

function countdown(deadlineAt: string | null): string {
  const days = daysUntil(deadlineAt);
  if (days === null) return "";
  if (days < 0) return " · passed";
  if (days === 0) return " · today";
  return ` · in ${days} day${days === 1 ? "" : "s"}`;
}

export default function ScholarshipsPage() {
  const [workspace, setWorkspace] = useState<Workspace | null>(null);
  const [items, setItems] = useState<Scholarship[]>([]);
  const [draft, setDraft] = useState<ScholarshipDraft>(() => blankDraft());
  const [editing, setEditing] = useState<Scholarship | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [region, setRegion] = useState("");
  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const fileRef = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const ws = (await apiRequest<Workspace[]>("/workspaces")).data[0] ?? null;
      setWorkspace(ws);
      setItems(ws ? await listScholarships(ws.id) : []);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not load scholarship applications. Please retry.");
    } finally {
      setLoading(false);
    }
  }, []);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void load(); }, [load]);

  const regions = useMemo(() => {
    const found = new Set(items.map((item) => item.region));
    return [...REGION_SUGGESTIONS.filter((r) => found.has(r)), ...[...found].filter((r) => !REGION_SUGGESTIONS.includes(r)).sort()];
  }, [items]);

  const metrics = useMemo(() => ({
    total: items.length,
    preparing: items.filter((i) => i.status === "preparing").length,
    submitted: items.filter((i) => i.status === "submitted" || i.status === "under_review").length,
    accepted: items.filter((i) => i.status === "accepted").length,
  }), [items]);

  const upcoming = useMemo(() => items
    .filter((i) => !CLOSED.includes(i.status) && i.deadline_at && (daysUntil(i.deadline_at) ?? -1) >= 0)
    .sort((a, b) => (a.deadline_at ?? "").localeCompare(b.deadline_at ?? ""))
    .slice(0, 5), [items]);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return items.filter((item) => (!region || item.region === region)
      && (!statusFilter || item.status === statusFilter)
      && (!q || [item.university, item.program, item.scheme].some((v) => (v ?? "").toLowerCase().includes(q))));
  }, [items, region, statusFilter, query]);

  function startNew() {
    setEditing(null);
    setDraft(blankDraft(region || "Russia"));
    setShowForm(true);
    setError("");
    setNotice("");
  }

  function startEdit(item: Scholarship) {
    setEditing(item);
    setDraft(draftFromScholarship(item));
    setShowForm(true);
    setError("");
    setNotice("");
  }

  function closeForm() {
    setShowForm(false);
    setEditing(null);
  }

  function set<K extends keyof ScholarshipDraft>(key: K, value: ScholarshipDraft[K]) {
    setDraft((current) => ({ ...current, [key]: value }));
  }
  const text = (key: "program" | "scheme" | "portal_link" | "opens_label" | "documents_required" | "funding" | "notes") =>
    (e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => set(key, e.target.value || null);

  // Runs one write, then reloads. Errors are shown, never thrown.
  async function run(work: () => Promise<string>) {
    setBusy(true);
    setError("");
    setNotice("");
    try {
      setNotice(await work());
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "That change could not be saved.");
    } finally {
      setBusy(false);
    }
  }

  async function writeOne(change: Parameters<typeof pushChanges>[1][number], success: string) {
    const result = await pushChanges(workspace!.id, [change]);
    if (result.rejected) throw new Error(result.firstError ?? "The change was rejected.");
    return success;
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!workspace) return;
    const id = editing?.id ?? crypto.randomUUID();
    await run(async () => {
      const message = await writeOne(
        { id, operation: editing ? "update" : "create", changes: toChanges(draft), baseVersion: editing?.version },
        editing ? "Application updated." : "Application added.",
      );
      closeForm();
      return message;
    });
  }

  async function changeStatus(item: Scholarship, status: ScholarshipStatus) {
    if (!workspace) return;
    await run(() => writeOne({ id: item.id, operation: "update", changes: { status }, baseVersion: item.version }, "Status updated."));
  }

  async function remove(item: Scholarship) {
    if (!workspace || !window.confirm(`Delete “${item.university}” from your scholarship tracker?`)) return;
    await run(() => writeOne({ id: item.id, operation: "delete", baseVersion: item.version }, "Application deleted."));
  }

  async function importDrafts(drafts: ScholarshipDraft[], skipped: string[]) {
    if (!workspace) return;
    await run(async () => {
      const result = await pushChanges(workspace.id, drafts.map((d) => ({ id: crypto.randomUUID(), operation: "create" as const, changes: toChanges(d) })));
      const problems = skipped.length + result.rejected;
      const base = `Imported ${result.accepted} application${result.accepted === 1 ? "" : "s"}${problems ? `, ${problems} skipped` : ""}.`;
      if (result.rejected) throw new Error(`${base} ${result.firstError ?? ""}`.trim());
      return skipped.length ? `${base} ${skipped[0]}` : base;
    });
  }

  async function onFile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    const { drafts, errors } = scholarshipsFromCsv(await file.text());
    if (!drafts.length) { setNotice(""); setError(errors[0] ?? "No usable rows were found in that file."); return; }
    await importDrafts(drafts, errors);
  }

  function exportCsv() {
    const url = URL.createObjectURL(new Blob([scholarshipsToCsv(items)], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = url;
    link.download = `scholarship-tracker-${new Date().toISOString().slice(0, 10)}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  }

  const empty = !loading && items.length === 0;

  return (
    <div className="page-content scholarships-page">
      <div className="page-heading">
        <div>
          <p className="eyebrow">Funding workspace</p>
          <h1>Scholarships</h1>
          <p className="page-lede">Track each university application: deadline, status, document checklist and funding.</p>
        </div>
        <div className="grant-card-actions">
          <button className="button button-secondary" type="button" onClick={() => fileRef.current?.click()} disabled={!workspace || busy}>Import CSV</button>
          <button className="button button-secondary" type="button" onClick={exportCsv} disabled={!items.length}>Export CSV</button>
          <button className="button button-primary" type="button" onClick={startNew} disabled={!workspace}>Add application</button>
        </div>
      </div>
      <input ref={fileRef} type="file" accept=".csv,text/csv" hidden onChange={(e) => void onFile(e)} aria-label="Import scholarship CSV" />

      {error && <div className="notice notice-error" role="alert">{error}</div>}
      {notice && <div className="notice" role="status">{notice}</div>}

      <div className="scholarship-metrics" aria-label="Application summary">
        <div><b>{metrics.total}</b><span>Target universities</span></div>
        <div><b>{metrics.preparing}</b><span>In preparation</span></div>
        <div><b>{metrics.submitted}</b><span>Submitted / in review</span></div>
        <div><b>{metrics.accepted}</b><span>Accepted</span></div>
      </div>

      {upcoming.length > 0 && (
        <section className="panel scholarship-upcoming" aria-labelledby="upcoming-title">
          <h2 id="upcoming-title">Next deadlines</h2>
          <ul>
            {upcoming.map((item) => (
              <li key={item.id}><b>{item.university}</b><span>{item.region} · {dateLabel(item.deadline_at)}{countdown(item.deadline_at)}</span></li>
            ))}
          </ul>
        </section>
      )}

      {showForm && (
        <section className="panel grant-form-panel" aria-labelledby="scholarship-form-title">
          <div className="panel-heading">
            <div>
              <p className="eyebrow">Application details</p>
              <h2 id="scholarship-form-title">{editing ? "Edit application" : "New application"}</h2>
            </div>
            <button className="button button-secondary" type="button" onClick={closeForm}>Cancel</button>
          </div>
          <form className="grant-form" onSubmit={(e) => void save(e)}>
            <div className="grant-form-grid">
              <label>University<input required maxLength={240} value={draft.university} onChange={(e) => set("university", e.target.value)} /></label>
              <label>Region / country<input required maxLength={80} list="scholarship-regions" value={draft.region} onChange={(e) => set("region", e.target.value)} /></label>
              <label>Program<input maxLength={500} value={draft.program ?? ""} onChange={text("program")} /></label>
              <label>Scheme / funding guarantee<input maxLength={500} value={draft.scheme ?? ""} onChange={text("scheme")} /></label>
              <label>Application status<select value={draft.status} onChange={(e) => set("status", e.target.value as ScholarshipStatus)}>{STATUSES.map((s) => <option key={s} value={s}>{label(s)}</option>)}</select></label>
              <label>Deadline<input type="date" value={draft.deadline ?? ""} onChange={(e) => set("deadline", e.target.value || null)} /></label>
              <label>Opens<input maxLength={120} value={draft.opens_label ?? ""} onChange={text("opens_label")} placeholder="e.g. September 1" /></label>
              <label>Portal link<input type="url" value={draft.portal_link ?? ""} onChange={text("portal_link")} placeholder="https://…" /></label>
              {CHECKLIST.map(({ key, label: stepLabel }) => (
                <label key={key}>{stepLabel}<select value={draft[key]} onChange={(e) => set(key, e.target.value as ScholarshipDraft[typeof key])}>{STEPS.map((s) => <option key={s} value={s}>{label(s)}</option>)}</select></label>
              ))}
              <label>Documents required<input maxLength={2000} value={draft.documents_required ?? ""} onChange={text("documents_required")} /></label>
              <label>Scholarship / funding<input maxLength={1000} value={draft.funding ?? ""} onChange={text("funding")} /></label>
            </div>
            <datalist id="scholarship-regions">{REGION_SUGGESTIONS.map((r) => <option key={r} value={r} />)}</datalist>
            <label>Notes and follow-ups<textarea maxLength={20000} rows={4} value={draft.notes ?? ""} onChange={text("notes")} /></label>
            <div className="grant-form-actions">
              <button className="button button-primary" type="submit" disabled={busy}>{busy ? "Saving…" : editing ? "Save changes" : "Add application"}</button>
              <button className="button button-secondary" type="button" onClick={closeForm} disabled={busy}>Cancel</button>
            </div>
          </form>
        </section>
      )}

      <section className="panel grants-panel" aria-labelledby="scholarship-list-title">
        <div className="panel-heading grants-toolbar">
          <div>
            <p className="eyebrow">Your workspace</p>
            <h2 id="scholarship-list-title">{visible.length} of {items.length} {items.length === 1 ? "application" : "applications"}</h2>
          </div>
          <div className="grant-filters">
            <label>Search<input type="search" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="University, program, scheme" /></label>
            <label>Status<select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}><option value="">All statuses</option>{STATUSES.map((s) => <option key={s} value={s}>{label(s)}</option>)}</select></label>
          </div>
        </div>

        {regions.length > 0 && (
          <div className="scholarship-tabs" role="group" aria-label="Filter by region">
            {["", ...regions].map((r) => (
              <button key={r || "all"} type="button" aria-pressed={region === r} className={region === r ? "active" : ""} onClick={() => setRegion(r)}>{r || "All regions"}</button>
            ))}
          </div>
        )}

        {loading ? <p className="grant-empty">Loading scholarship applications…</p> : empty ? (
          <div className="grant-empty">
            <h3>No applications tracked yet.</h3>
            <p>Add one, import a CSV, or load your starter list of {STARTER_APPLICATIONS.length} universities across Russia, the Czech Republic, Australia and the USA.</p>
            <button className="button button-primary" type="button" disabled={!workspace || busy} onClick={() => void importDrafts(STARTER_APPLICATIONS, [])}>
              {busy ? "Importing…" : `Load starter list (${STARTER_APPLICATIONS.length})`}
            </button>
          </div>
        ) : visible.length ? (
          <div className="grant-list">
            {visible.map((item) => {
              const progress = checklistProgress(item);
              return (
                <article className="grant-card" key={item.id}>
                  <div className="grant-card-heading">
                    <div>
                      <p className="eyebrow">{item.region}</p>
                      <h3>{item.portal_link ? <a href={item.portal_link} target="_blank" rel="noreferrer">{item.university}</a> : item.university}</h3>
                      {item.program && <p className="grant-organisation">{item.program}</p>}
                    </div>
                    <span className="status-badge">{label(item.status)}</span>
                  </div>
                  <div className="grant-facts">
                    <span><b>Deadline</b>{dateLabel(item.deadline_at)}{countdown(item.deadline_at)}</span>
                    {item.scheme && <span><b>Scheme</b>{item.scheme}</span>}
                    {item.funding && <span><b>Funding</b>{item.funding}</span>}
                  </div>
                  <div className="scholarship-progress" role="img" aria-label={`Checklist ${progress}% done`}>
                    <div><i style={{ width: `${progress}%` }} /></div><span>{progress}% of checklist</span>
                  </div>
                  <ul className="scholarship-checklist">
                    {CHECKLIST.map(({ key, label: stepLabel }) => <li key={key} data-step={item[key]}>{stepLabel}: {label(item[key])}</li>)}
                  </ul>
                  {item.notes && <p className="grant-notes">{item.notes}</p>}
                  <div className="grant-card-actions">
                    <label className="scholarship-status-select">Status
                      <select value={item.status} disabled={busy} onChange={(e) => void changeStatus(item, e.target.value as ScholarshipStatus)}>
                        {STATUSES.map((s) => <option key={s} value={s}>{label(s)}</option>)}
                      </select>
                    </label>
                    <button className="button button-secondary" type="button" onClick={() => startEdit(item)}>Edit</button>
                    <button className="button button-danger" type="button" onClick={() => void remove(item)} disabled={busy}>Delete</button>
                  </div>
                </article>
              );
            })}
          </div>
        ) : (
          <div className="grant-empty"><h3>No matching applications.</h3><p>Change the search, status or region filter.</p></div>
        )}
      </section>
    </div>
  );
}
