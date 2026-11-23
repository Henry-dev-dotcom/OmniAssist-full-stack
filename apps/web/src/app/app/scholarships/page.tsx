"use client";

import type { ChangeEvent } from "react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { apiRequest } from "@/lib/api/client";
import type { Workspace } from "@/lib/types/domain";
import { ApplicationForm, SchemeForm, SectionForm } from "@/components/scholarships/forms";
import { STARTER_SECTIONS } from "@/lib/scholarships/starter";
import {
  loadTracker, pushChanges, removeSectionChanges, restoreApplicationChange, restoreSchemeChange, restoreSectionChanges,
  starterChanges, type Change,
} from "@/lib/scholarships/api";
import { UndoBar } from "@/components/undo-bar";
import { scholarshipsFromCsv, scholarshipsToCsv } from "@/lib/scholarships/csv";
import {
  CHECKLIST, CLOSED, STATUSES, blankDraft, checklistProgress, daysUntil, draftFromScholarship, label,
  sameName, schemeChanges, sectionChanges, toChanges,
  type Scholarship, type ScholarshipDraft, type ScholarshipStatus, type Scheme, type SchemeDraft,
  type Section, type SectionDraft, type StarterSection,
} from "@/lib/scholarships/types";

type Open =
  | null
  | { kind: "section"; editing: Section | null }
  | { kind: "scheme"; editing: Scheme | null }
  | { kind: "application"; editing: Scholarship | null };

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

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;
const starterSummary = (s: StarterSection) =>
  [plural(s.applications.length, "application"), s.schemes.length ? plural(s.schemes.length, "scheme") : ""].filter(Boolean).join(", ");

export default function ScholarshipsPage() {
  const [workspace, setWorkspace] = useState<Workspace | null>(null);
  const [sections, setSections] = useState<Section[]>([]);
  const [schemes, setSchemes] = useState<Scheme[]>([]);
  const [items, setItems] = useState<Scholarship[]>([]);
  const [open, setOpen] = useState<Open>(null);
  const [sectionId, setSectionId] = useState("");
  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  // The last delete, kept briefly so it can be undone.
  const [undo, setUndo] = useState<{ message: string; changes: Change[] } | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const ws = (await apiRequest<Workspace[]>("/workspaces")).data[0] ?? null;
      setWorkspace(ws);
      const tracker = ws ? await loadTracker(ws.id) : { sections: [], schemes: [], applications: [] };
      setSections(tracker.sections);
      setSchemes(tracker.schemes);
      setItems(tracker.applications);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not load the scholarship tracker. Please retry.");
    } finally {
      setLoading(false);
    }
  }, []);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void load(); }, [load]);

  // The selected tab, unless that section has since been removed.
  const current = sections.find((s) => s.id === sectionId) ?? null;
  const sectionName = useMemo(() => new Map(sections.map((s) => [s.id, s.name])), [sections]);
  const missingStarters = STARTER_SECTIONS.filter((starter) => !sections.some((s) => sameName(s.name, starter.name)));
  const nextPosition = sections.reduce((max, s) => Math.max(max, s.position + 1), 0);

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
    return items.filter((item) => (!current || item.section_id === current.id)
      && (!statusFilter || item.status === statusFilter)
      && (!q || [item.university, item.program, item.scheme].some((v) => (v ?? "").toLowerCase().includes(q))));
  }, [items, current, statusFilter, query]);
  const currentSchemes = current ? schemes.filter((s) => s.section_id === current.id) : [];

  function show(next: Open) {
    setOpen(next);
    setError("");
    setNotice("");
  }

  // Sends changes, reports the outcome, reloads. Errors are shown, never thrown.
  async function run(changes: Change[], success: string, after?: () => void) {
    if (!workspace) return;
    setUndo(null);
    setBusy(true);
    setError("");
    setNotice("");
    try {
      const result = await pushChanges(workspace.id, changes);
      if (result.rejected) {
        const partial = result.accepted ? ` ${result.accepted} of ${changes.length} changes were saved.` : "";
        setError(`${result.firstError ?? "The change was rejected."}${partial}`);
      } else {
        setNotice(success);
        after?.();
      }
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "That change could not be saved.");
    } finally {
      setBusy(false);
    }
  }

  function undoLast() {
    if (!undo) return;
    void run(undo.changes, undo.message.replace(/ (deleted|removed)\.$/, " restored."));
  }

  // --- sections ---

  function saveSection(draft: SectionDraft) {
    const editing = open?.kind === "section" ? open.editing : null;
    if (sections.some((s) => s.id !== editing?.id && sameName(s.name, draft.name))) {
      setError(`A section named “${draft.name.trim()}” already exists.`);
      return;
    }
    const id = editing?.id ?? crypto.randomUUID();
    void run(
      [editing
        ? { entity: "scholarship_section", id, operation: "update", changes: sectionChanges(draft), baseVersion: editing.version }
        : { entity: "scholarship_section", id, operation: "create", changes: { ...sectionChanges(draft), position: nextPosition } }],
      editing ? "Section updated." : `Section “${draft.name.trim()}” created.`,
      () => { setOpen(null); setSectionId(id); },
    );
  }

  function addStarters(starters: StarterSection[]) {
    const changes = starters.flatMap((starter, index) => starterChanges(starter, nextPosition + index));
    const applications = starters.reduce((n, s) => n + s.applications.length, 0);
    void run(changes, `Added ${plural(starters.length, "section")} with ${plural(applications, "application")}.`, () => setOpen(null));
  }

  function removeSection(section: Section) {
    const apps = items.filter((i) => i.section_id === section.id).length;
    const routes = schemes.filter((s) => s.section_id === section.id).length;
    const contents = apps || routes ? ` This also deletes its ${plural(apps, "application")} and ${plural(routes, "scheme")}.` : "";
    if (!window.confirm(`Remove the “${section.name}” section?${contents}`)) return;
    const restore = restoreSectionChanges(section, schemes, items);
    void run(removeSectionChanges(section, schemes, items), "", () => {
      setSectionId("");
      setUndo({ message: `Section “${section.name}” removed.`, changes: restore });
    });
  }

  // --- schemes ---

  function saveScheme(draft: SchemeDraft) {
    if (!current) return;
    const editing = open?.kind === "scheme" ? open.editing : null;
    void run(
      [editing
        ? { entity: "scholarship_scheme", id: editing.id, operation: "update", changes: schemeChanges(draft, editing.section_id), baseVersion: editing.version }
        : { entity: "scholarship_scheme", id: crypto.randomUUID(), operation: "create", changes: { ...schemeChanges(draft, current.id), position: currentSchemes.reduce((max, s) => Math.max(max, s.position + 1), 0) } }],
      editing ? "Scheme updated." : "Scheme added.",
      () => setOpen(null),
    );
  }

  function removeScheme(scheme: Scheme) {
    void run([{ entity: "scholarship_scheme", id: scheme.id, operation: "delete", baseVersion: scheme.version }], "",
      () => setUndo({ message: `Scheme “${scheme.name}” deleted.`, changes: [restoreSchemeChange(scheme)] }));
  }

  // --- applications ---

  function saveApplication(draft: ScholarshipDraft, toSection: string) {
    const editing = open?.kind === "application" ? open.editing : null;
    void run(
      [{ entity: "scholarship_application", id: editing?.id ?? crypto.randomUUID(), operation: editing ? "update" : "create", changes: toChanges(draft, toSection), baseVersion: editing?.version }],
      editing ? "Application updated." : "Application added.",
      () => setOpen(null),
    );
  }

  function changeStatus(item: Scholarship, status: ScholarshipStatus) {
    void run([{ entity: "scholarship_application", id: item.id, operation: "update", changes: { status }, baseVersion: item.version }], "Status updated.");
  }

  function removeApplication(item: Scholarship) {
    void run([{ entity: "scholarship_application", id: item.id, operation: "delete", baseVersion: item.version }], "",
      () => setUndo({ message: `“${item.university}” deleted.`, changes: [restoreApplicationChange(item)] }));
  }

  // --- CSV ---

  async function onFile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    const { rows, errors } = scholarshipsFromCsv(await file.text());
    if (!rows.length) { setNotice(""); setError(errors[0] ?? "No usable rows were found in that file."); return; }
    // Sections named in the file that do not exist yet are created first.
    const ids = new Map(sections.map((s) => [s.name.trim().toLowerCase(), s.id]));
    const changes: Change[] = [];
    let created = 0;
    for (const row of rows) {
      const key = row.section.toLowerCase();
      if (!ids.has(key)) {
        const id = crypto.randomUUID();
        ids.set(key, id);
        changes.push({ entity: "scholarship_section", id, operation: "create", changes: { name: row.section, description: null, position: nextPosition + created } });
        created += 1;
      }
    }
    for (const row of rows) {
      changes.push({ entity: "scholarship_application", id: crypto.randomUUID(), operation: "create", changes: toChanges(row.draft, ids.get(row.section.toLowerCase())!) });
    }
    const skipped = errors.length ? ` ${plural(errors.length, "row")} skipped: ${errors[0]}` : "";
    const made = created ? ` ${plural(created, "new section")} created.` : "";
    await run(changes, `Imported ${plural(rows.length, "application")}.${made}${skipped}`);
  }

  function exportCsv() {
    const url = URL.createObjectURL(new Blob([scholarshipsToCsv(items, sections)], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = url;
    link.download = `scholarship-tracker-${new Date().toISOString().slice(0, 10)}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  }

  const noSections = !loading && sections.length === 0;

  return (
    <div className="page-content scholarships-page">
      <div className="page-heading">
        <div>
          <p className="eyebrow">Funding workspace</p>
          <h1>Scholarships</h1>
          <p className="page-lede">Organise applications into sections, and track each deadline, document checklist and funding route.</p>
        </div>
        <div className="grant-card-actions">
          <button className="button button-secondary" type="button" onClick={() => fileRef.current?.click()} disabled={!workspace || busy}>Import CSV</button>
          <button className="button button-secondary" type="button" onClick={exportCsv} disabled={!items.length}>Export CSV</button>
          <button className="button button-secondary" type="button" onClick={() => show({ kind: "section", editing: null })} disabled={!workspace}>New section</button>
          <button className="button button-primary" type="button" onClick={() => show({ kind: "application", editing: null })} disabled={!sections.length}>Add application</button>
        </div>
      </div>
      <input ref={fileRef} type="file" accept=".csv,text/csv" hidden onChange={(e) => void onFile(e)} aria-label="Import scholarship CSV" />

      {error && <div className="notice notice-error" role="alert">{error}</div>}
      {notice && <div className="notice" role="status">{notice}</div>}
      {undo && <UndoBar message={undo.message} busy={busy} onUndo={undoLast} onDismiss={() => setUndo(null)} />}

      <div className="scholarship-metrics" aria-label="Application summary">
        <div><b>{metrics.total}</b><span>Target universities</span></div>
        <div><b>{metrics.preparing}</b><span>In preparation</span></div>
        <div><b>{metrics.submitted}</b><span>Submitted / in review</span></div>
        <div><b>{metrics.accepted}</b><span>Accepted</span></div>
      </div>

      {open?.kind === "section" && (
        <>
          <SectionForm
            key={open.editing?.id ?? "new"}
            initial={{ name: open.editing?.name ?? "", description: open.editing?.description ?? null }}
            editing={Boolean(open.editing)} busy={busy} onCancel={() => setOpen(null)} onSubmit={saveSection}
          />
          {!open.editing && missingStarters.length > 0 && (
            <section className="panel scholarship-starters" aria-labelledby="starters-title">
              <h2 id="starters-title">Or add a section from your tracker</h2>
              <p>These come from your original spreadsheet, with their universities and schemes filled in.</p>
              <ul>
                {missingStarters.map((starter) => (
                  <li key={starter.name}>
                    <div><b>{starter.name}</b><span>{starterSummary(starter)}</span></div>
                    <button className="button button-secondary" type="button" disabled={busy} onClick={() => addStarters([starter])}>Add section</button>
                  </li>
                ))}
              </ul>
              {missingStarters.length > 1 && <button className="button button-primary" type="button" disabled={busy} onClick={() => addStarters(missingStarters)}>Add all {missingStarters.length} sections</button>}
            </section>
          )}
        </>
      )}

      {open?.kind === "scheme" && current && (
        <SchemeForm
          key={open.editing?.id ?? "new"}
          initial={open.editing ?? { name: "", organizing_body: null, coverage: null, strategy: null }}
          editing={Boolean(open.editing)} busy={busy} onCancel={() => setOpen(null)} onSubmit={saveScheme}
        />
      )}

      {open?.kind === "application" && sections.length > 0 && (
        <ApplicationForm
          key={open.editing?.id ?? "new"}
          initial={open.editing ? draftFromScholarship(open.editing) : blankDraft()}
          initialSectionId={open.editing?.section_id ?? current?.id ?? sections[0].id}
          sections={sections} editing={Boolean(open.editing)} busy={busy}
          onCancel={() => setOpen(null)} onSubmit={saveApplication}
        />
      )}

      {loading && !sections.length ? <p className="grant-empty">Loading the scholarship tracker…</p> : noSections ? (
        <section className="panel grants-panel">
          <div className="grant-empty">
            <h3>No sections yet.</h3>
            <p>A section groups applications, for example by country or degree level. Create your own, or bring in your tracker: {STARTER_SECTIONS.map((s) => s.name).join(", ")}.</p>
            <div className="grant-card-actions scholarship-centered">
              <button className="button button-primary" type="button" disabled={!workspace || busy} onClick={() => addStarters(STARTER_SECTIONS)}>
                {busy ? "Adding…" : `Add my tracker (${plural(STARTER_SECTIONS.length, "section")})`}
              </button>
              <button className="button button-secondary" type="button" disabled={!workspace || busy} onClick={() => show({ kind: "section", editing: null })}>New section</button>
            </div>
          </div>
        </section>
      ) : (
        <>
          <div className="scholarship-tabs" role="group" aria-label="Sections">
            <button type="button" aria-pressed={!current} className={!current ? "active" : ""} onClick={() => setSectionId("")}>All sections</button>
            {sections.map((s) => (
              <button key={s.id} type="button" aria-pressed={current?.id === s.id} className={current?.id === s.id ? "active" : ""} onClick={() => setSectionId(s.id)}>
                {s.name} <small>{items.filter((i) => i.section_id === s.id).length}</small>
              </button>
            ))}
            <button type="button" className="scholarship-tab-add" onClick={() => show({ kind: "section", editing: null })}>+ New section</button>
          </div>

          {!current && upcoming.length > 0 && (
            <section className="panel scholarship-upcoming" aria-labelledby="upcoming-title">
              <h2 id="upcoming-title">Next deadlines</h2>
              <ul>
                {upcoming.map((item) => (
                  <li key={item.id}><b>{item.university}</b><span>{sectionName.get(item.section_id)} · {dateLabel(item.deadline_at)}{countdown(item.deadline_at)}</span></li>
                ))}
              </ul>
            </section>
          )}

          {current && (
            <section className="panel scholarship-section" aria-labelledby="section-title">
              <div className="panel-heading">
                <div>
                  <p className="eyebrow">Section</p>
                  <h2 id="section-title">{current.name}</h2>
                  {current.description && <p className="scholarship-section-description">{current.description}</p>}
                </div>
                <div className="grant-card-actions">
                  <button className="button button-secondary" type="button" onClick={() => show({ kind: "section", editing: current })}>Edit section</button>
                  <button className="button button-danger" type="button" disabled={busy} onClick={() => removeSection(current)}>Remove section</button>
                </div>
              </div>
              <div className="scholarship-schemes-heading">
                <h3>Scholarship schemes</h3>
                <button className="button button-secondary" type="button" onClick={() => show({ kind: "scheme", editing: null })}>Add scheme</button>
              </div>
              {currentSchemes.length ? (
                <div className="scholarship-schemes">
                  {currentSchemes.map((scheme) => (
                    <article key={scheme.id}>
                      <h4>{scheme.name}</h4>
                      {scheme.organizing_body && <p className="grant-organisation">{scheme.organizing_body}</p>}
                      {scheme.coverage && <p><b>Covers</b>{scheme.coverage}</p>}
                      {scheme.strategy && <p><b>Strategy and next steps</b>{scheme.strategy}</p>}
                      <div className="grant-card-actions">
                        <button className="button button-secondary" type="button" onClick={() => show({ kind: "scheme", editing: scheme })}>Edit</button>
                        <button className="button button-danger" type="button" disabled={busy} onClick={() => removeScheme(scheme)}>Delete</button>
                      </div>
                    </article>
                  ))}
                </div>
              ) : <p className="scholarship-muted">No schemes recorded for this section yet.</p>}
            </section>
          )}

          <section className="panel grants-panel" aria-labelledby="scholarship-list-title">
            <div className="panel-heading grants-toolbar">
              <div>
                <p className="eyebrow">{current ? current.name : "All sections"}</p>
                <h2 id="scholarship-list-title">{visible.length} of {plural(current ? items.filter((i) => i.section_id === current.id).length : items.length, "application")}</h2>
              </div>
              <div className="grant-filters">
                <label>Search<input type="search" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="University, program, scheme" /></label>
                <label>Status<select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}><option value="">All statuses</option>{STATUSES.map((s) => <option key={s} value={s}>{label(s)}</option>)}</select></label>
              </div>
            </div>

            {visible.length ? (
              <div className="grant-list">
                {visible.map((item) => {
                  const progress = checklistProgress(item);
                  return (
                    <article className="grant-card" key={item.id}>
                      <div className="grant-card-heading">
                        <div>
                          <p className="eyebrow">{sectionName.get(item.section_id)}</p>
                          <h3>{item.portal_link ? <a href={item.portal_link} target="_blank" rel="noreferrer">{item.university}</a> : item.university}</h3>
                          {item.program && <p className="grant-organisation">{item.program}</p>}
                        </div>
                        <span className="status-badge">{label(item.status)}</span>
                      </div>
                      <div className="grant-facts">
                        <span><b>Deadline</b>{dateLabel(item.deadline_at)}{countdown(item.deadline_at)}</span>
                        {item.opens_label && <span><b>Opens</b>{item.opens_label}</span>}
                        {item.scheme && <span><b>Scheme</b>{item.scheme}</span>}
                        {item.funding && <span><b>Funding</b>{item.funding}</span>}
                        {item.documents_required && <span><b>Documents required</b>{item.documents_required}</span>}
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
                          <select value={item.status} disabled={busy} onChange={(e) => changeStatus(item, e.target.value as ScholarshipStatus)}>
                            {STATUSES.map((s) => <option key={s} value={s}>{label(s)}</option>)}
                          </select>
                        </label>
                        {item.portal_link && (
                          <a className="button button-primary button-link" href={item.portal_link} target="_blank" rel="noopener noreferrer">
                            Visit site<span aria-hidden="true">↗</span><span className="sr-only"> for {item.university} (opens in a new tab)</span>
                          </a>
                        )}
                        <button className="button button-secondary" type="button" onClick={() => show({ kind: "application", editing: item })}>Edit</button>
                        <button className="button button-danger" type="button" onClick={() => removeApplication(item)} disabled={busy}>Delete</button>
                      </div>
                    </article>
                  );
                })}
              </div>
            ) : (
              <div className="grant-empty">
                <h3>{items.length && (query || statusFilter) ? "No matching applications." : "No applications here yet."}</h3>
                <p>{items.length && (query || statusFilter) ? "Change the search or status filter." : "Use Add application to start tracking a university in this section."}</p>
              </div>
            )}
          </section>
        </>
      )}
    </div>
  );
}
