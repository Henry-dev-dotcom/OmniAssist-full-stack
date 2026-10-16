"use client";
import { ChangeEvent, FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { apiRequest, apiUrl } from "@/lib/api/client";
import { previewCsv } from "@/lib/research/csv";
import type { Project, Workspace } from "@/lib/types/domain";
import { clearSession } from "@/lib/auth/session";
import { useRouter } from "next/navigation";

type Row = { id: string; [key: string]: unknown };
type Stage = { id: string; name: string; archived: boolean };
type Review = Row & { project_id: string; name: string; stages: Stage[]; version: number };
type ResearchItem = Row & { title: string; status?: string; state?: string; version: number; stage_id?: string; notes?: string | null; updated_at?: string };
type SearchResult = Row & { title: string; entity_type: string; status?: string; updated_at?: string };
type Notification = Row & { title: string; delivery_status: string; scheduled_at?: string };
type ExportJob = { id: string; status: string; format: string; download_url?: string; expires_at?: string };
type Profile = { id: string; display_name?: string; timezone?: string; preferences?: Record<string, unknown> };
type Tab = "reviews" | "analysis" | "experiments" | "search" | "notifications" | "exports" | "settings";
const tabs: { id: Tab; label: string }[] = [
  { id: "reviews", label: "Review board" }, { id: "analysis", label: "Analysis ledger" },
  { id: "experiments", label: "Experiment log" }, { id: "search", label: "Search" },
  { id: "notifications", label: "Notifications" }, { id: "exports", label: "Export data" }, { id: "settings", label: "Settings" },
];
const stagesDefault = ["Protocol", "Screening", "Full Text", "Extraction", "Synthesis"];
const initialForm: Record<string, string> = { title: "", purpose: "", language: "python", repository_url: "", branch_name: "", commit_ref: "", data_source_ref: "", environment: "", result_summary: "", error_details: "", next_action: "" };

function newId() { return crypto.randomUUID(); }
function csvCell(value: unknown) { return `"${String(value ?? "").replaceAll('"', '""')}"`; }

export default function ResearchPage() {
  const router = useRouter();
  const [tab, setTab] = useState<Tab>("reviews");
  const [workspace, setWorkspace] = useState<Workspace | null>(null);
  const [projects, setProjects] = useState<Project[]>([]);
  const [projectId, setProjectId] = useState("");
  const [reviews, setReviews] = useState<Review[]>([]);
  const [reviewId, setReviewId] = useState("");
  const [items, setItems] = useState<ResearchItem[]>([]);
  const [analyses, setAnalyses] = useState<ResearchItem[]>([]);
  const [experiments, setExperiments] = useState<ResearchItem[]>([]);
  const [selected, setSelected] = useState("");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  const [reviewName, setReviewName] = useState("");
  const [stageName, setStageName] = useState("");
  const [itemTitle, setItemTitle] = useState("");
  const [recordTitle, setRecordTitle] = useState("");
  const [analysisForm, setAnalysisForm] = useState(initialForm);
  const [experimentForm, setExperimentForm] = useState<Record<string, string>>(() => { if (typeof window !== "undefined") { try { const saved = localStorage.getItem("omniassist-experiment-draft"); if (saved) return { ...JSON.parse(saved) as Record<string, string> }; } catch { /* ignore malformed local draft */ } } return { title: "", objective: "", protocol: "", variables: "", materials: "", observations: "", deviations: "", result_summary: "", next_steps: "", occurred_at: "", template_type: "" }; });
  const [csvPreview, setCsvPreview] = useState<ReturnType<typeof previewCsv> | null>(null);
  const [csvMapping, setCsvMapping] = useState({ title: "", source_identifier: "", notes: "" });
  const [searchText, setSearchText] = useState("");
  const [searchType, setSearchType] = useState("");
  const [searchResults, setSearchResults] = useState<SearchResult[]>([]);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [exports, setExports] = useState<ExportJob[]>([]);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [quietStart, setQuietStart] = useState("22:00");
  const [quietEnd, setQuietEnd] = useState("07:00");
  const [confirmDelete, setConfirmDelete] = useState(false);

  const loadBase = useCallback(async () => {
    try {
      const ws = (await apiRequest<Workspace[]>("/workspaces")).data[0];
      setWorkspace(ws ?? null);
      if (!ws) return;
      const ps = (await apiRequest<Project[]>(`/projects?workspace_id=${ws.id}&view=all`)).data;
      setProjects(ps);
      setProjectId((current) => current || ps[0]?.id || "");
    } catch { setError("Research workspace is unavailable. Check your connection and try again."); }
  }, []);
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void loadBase(); }, [loadBase]);

  const loadResearch = useCallback(async () => {
    if (!workspace || !projectId) return;
    try {
      const [rs, as, es] = await Promise.all([
        apiRequest<Review[]>(`/reviews?workspace_id=${workspace.id}&project_id=${projectId}`),
        apiRequest<ResearchItem[]>(`/analysis-records?workspace_id=${workspace.id}&project_id=${projectId}`),
        apiRequest<ResearchItem[]>(`/experiment-entries?workspace_id=${workspace.id}&project_id=${projectId}`),
      ]);
      setReviews(rs.data); setAnalyses(as.data); setExperiments(es.data);
      const rid = reviewId && rs.data.some((r) => r.id === reviewId) ? reviewId : rs.data[0]?.id ?? "";
      setReviewId(rid);
      if (rid) setItems((await apiRequest<ResearchItem[]>(`/reviews/${rid}/items`)).data); else setItems([]);
      setError("");
    } catch { setError("Could not load research records. Please retry."); }
  }, [workspace, projectId, reviewId]);
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void loadResearch(); }, [loadResearch]);

  async function push(entityType: string, id: string, operation: "create" | "update", changes: Record<string, unknown>, version?: number) {
    if (!workspace) throw new Error("Choose a workspace first.");
    const response = await apiRequest<{ results: { status: string; message?: string; error_code?: string }[] }>("/sync/push", {
      method: "POST", body: { device_id: newId(), protocol_version: 1, cursor: 0, mutations: [{ mutation_id: newId(), workspace_id: workspace.id, entity_type: entityType, entity_id: id, operation, base_version: version, changes }] },
    });
    const result = response.data.results[0];
    if (result?.status !== "accepted") throw new Error(result?.message ?? `The ${entityType.replaceAll("_", " ")} change was rejected (${result?.error_code ?? "unknown error"}).`);
  }
  async function act(action: () => Promise<void>, success?: string) {
    setBusy(true); setError(""); setNotice("");
    try { await action(); if (success) setNotice(success); await loadResearch(); }
    catch (e) { setError(e instanceof Error ? e.message : "The change could not be saved. Your form is still available to retry."); }
    finally { setBusy(false); }
  }

  async function createReview(event: FormEvent) {
    event.preventDefault(); if (!workspace || !projectId || !reviewName.trim()) return;
    const id = newId(); const stages = stagesDefault.map((name) => ({ id: newId(), name, archived: false }));
    await act(async () => { await push("review", id, "create", { project_id: projectId, name: reviewName.trim(), description: "", stages }); setReviewName(""); setReviewId(id); }, "Review created with the default stages.");
  }
  async function createItem(event: FormEvent) {
    event.preventDefault(); if (!workspace || !reviewId || !itemTitle.trim()) return;
    const review = reviews.find((r) => r.id === reviewId); const stage = review?.stages.find((s) => !s.archived);
    if (!stage) { setError("Add an active stage to this review first."); return; }
    const id = newId();
    await act(async () => { await push("review_item", id, "create", { review_id: reviewId, stage_id: stage.id, title: itemTitle.trim(), tags: [], notes: "" }); setItemTitle(""); }, "Review item added.");
  }
  async function moveItem(item: ResearchItem, stageId: string) {
    if (item.stage_id === stageId) return;
    await act(() => push("review_item", item.id, "update", { stage_id: stageId }, item.version), "Stage updated; the move is recorded in review history.");
  }
  async function saveStages(stages: Stage[]) {
    if (!currentReview) return;
    await act(() => push("review", currentReview.id, "update", { stages }, currentReview.version), "Review stages saved.");
  }
  async function importCsv() {
    if (!csvPreview || csvMappingErrors.length || !reviewId) return;
    const review = reviews.find((r) => r.id === reviewId); const stage = review?.stages.find((s) => !s.archived);
    if (!workspace || !stage) return;
    await act(async () => {
      const titleIndex = csvPreview.headers.indexOf(csvMapping.title);
      const sourceIndex = csvPreview.headers.indexOf(csvMapping.source_identifier);
      const notesIndex = csvPreview.headers.indexOf(csvMapping.notes);
      const ids = csvPreview.rows.map(newId);
      for (let offset = 0; offset < ids.length; offset += 100) {
        const mutations = ids.slice(offset, offset + 100).map((id, i) => {
          const row = csvPreview.rows[offset + i];
          return { mutation_id: newId(), workspace_id: workspace.id, entity_type: "review_item", entity_id: id, operation: "create", changes: { review_id: reviewId, stage_id: stage.id, title: row[titleIndex].trim(), source_identifier: sourceIndex >= 0 ? row[sourceIndex].trim() : null, notes: notesIndex >= 0 ? row[notesIndex] : "", tags: [] } };
        });
        const result = await apiRequest<{ results: { status: string; message?: string }[] }>("/sync/push", { method: "POST", body: { device_id: newId(), protocol_version: 1, cursor: 0, mutations } });
        if (result.data.results.some((r) => r.status !== "accepted")) throw new Error("Some imported rows were rejected. Review the current board and retry only the missing records.");
      }
      setCsvPreview(null);
    }, "CSV records imported.");
  }
  function downloadReviewCsv() {
    const review = reviews.find((r) => r.id === reviewId); if (!review) return;
    const lines = [["id", "title", "source_identifier", "stage", "decision", "notes"], ...items.map((item) => [item.id, item.title, item.source_identifier, review.stages.find((s) => s.id === item.stage_id)?.name, item.decision, item.notes])];
    const blob = new Blob([lines.map((line) => line.map(csvCell).join(",")).join("\r\n")], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob); const link = document.createElement("a"); link.href = url; link.download = "review-items.csv"; link.click(); URL.revokeObjectURL(url);
  }
  async function createAnalysis(event: FormEvent) {
    event.preventDefault(); if (!projectId || !recordTitle.trim()) return;
    const id = newId();
    await act(async () => { await push("analysis_record", id, "create", { ...analysisForm, project_id: projectId, title: recordTitle.trim(), status: "planned", repository_url: analysisForm.repository_url || null }); setRecordTitle(""); setAnalysisForm(initialForm); }, "Analysis record saved.");
  }
  async function updateAnalysis(row: ResearchItem, field: string, value: string) {
    await act(() => push("analysis_record", row.id, "update", { [field]: value }, row.version), "Analysis updated.");
  }
  async function addNextAction(row: ResearchItem) {
    if (!workspace || !row.next_action) return;
    await act(async () => { await apiRequest("/tasks", { method: "POST", body: { workspace_id: workspace.id, project_id: projectId, title: String(row.next_action), status: "todo", priority: "normal" } }); }, "Linked next-action task created.");
  }
  async function createExperiment(event: FormEvent) {
    event.preventDefault(); if (!projectId || !experimentForm.title.trim()) return;
    const id = newId();
    await act(async () => { await push("experiment_entry", id, "create", { ...experimentForm, template_type: experimentForm.template_type || null, project_id: projectId, occurred_at: new Date(experimentForm.occurred_at).toISOString(), state: "draft" }); setExperimentForm({ ...experimentForm, title: "" }); localStorage.removeItem("omniassist-experiment-draft"); }, "Draft experiment saved. It is not finalized.");
  }
  async function saveExperiment(row: ResearchItem, values: Record<string, unknown>) {
    await act(() => push("experiment_entry", row.id, "update", values, row.version), "Experiment draft saved.");
  }
  async function finalizeExperiment(row: ResearchItem) {
    await act(() => push("experiment_entry", row.id, "update", { state: "finalized" }, row.version), "Experiment finalized. Later edits are preserved as revisions.");
  }
  useEffect(() => {
    if (experimentForm.title || experimentForm.objective || experimentForm.protocol) localStorage.setItem("omniassist-experiment-draft", JSON.stringify(experimentForm));
  }, [experimentForm]);
  useEffect(() => {
    if (tab !== "experiments" || !selected) return;
    const row = experiments.find((r) => r.id === selected);
    if (row && row.state === "draft") localStorage.setItem(`omniassist-experiment-draft-${row.id}`, JSON.stringify(row));
  }, [tab, selected, experiments]);

  async function runSearch(event: FormEvent) {
    event.preventDefault(); if (!workspace || !searchText.trim()) return;
    setError("");
    try { const typeQuery = searchType ? `&type=${encodeURIComponent(searchType)}` : ""; setSearchResults((await apiRequest<SearchResult[]>(`/search?workspace_id=${workspace.id}&q=${encodeURIComponent(searchText.trim())}&limit=50${typeQuery}`)).data); }
    catch (e) { setError(e instanceof Error ? e.message : "Search could not be completed."); }
  }
  async function loadNotifications() {
    if (!workspace) return;
    try { setNotifications((await apiRequest<Notification[]>(`/notifications?workspace_id=${workspace.id}`)).data); }
    catch (e) { setError(e instanceof Error ? e.message : "Notifications could not be loaded."); }
  }
  async function notificationAction(id: string, action: "read" | "dismiss" | "ack") {
    await act(async () => { await apiRequest(`/notifications/${id}/${action}`, { method: "POST" }); await loadNotifications(); }, `Notification ${action === "read" ? "marked read" : action + "ed"}.`);
  }
  async function requestExport(format: "json" | "csv") {
    if (!workspace) return;
    await act(async () => {
      const job = (await apiRequest<ExportJob>("/exports", { method: "POST", body: { workspace_id: workspace.id, format } })).data;
      setExports((old) => [job, ...old]);
      await pollExport(job.id);
    }, "Export request submitted.");
  }
  async function pollExport(id: string) {
    const job = (await apiRequest<ExportJob>(`/exports/${id}`)).data;
    setExports((old) => [job, ...old.filter((item) => item.id !== id)]);
  }
  async function loadProfile() {
    try { const value = (await apiRequest<Profile>("/me")).data; setProfile(value); const preferences = value.preferences; const notifications = preferences?.notifications; if (notifications && typeof notifications === "object") { const quiet = (notifications as Record<string, unknown>).quiet_hours; if (quiet && typeof quiet === "object") { const hours = quiet as Record<string, unknown>; if (typeof hours.start === "string") setQuietStart(hours.start); if (typeof hours.end === "string") setQuietEnd(hours.end); } } }
    catch { setError("Profile settings could not be loaded."); }
  }
  async function saveProfile(event: FormEvent) {
    event.preventDefault(); if (!profile) return;
    const existing = profile.preferences?.notifications; const notifications = existing && typeof existing === "object" ? existing as Record<string, unknown> : {};
    const preferences = { ...profile.preferences, notifications: { ...notifications, quiet_hours: { start: quietStart, end: quietEnd } } };
    await act(async () => { setProfile((await apiRequest<Profile>("/me", { method: "PATCH", body: { display_name: profile.display_name, timezone: profile.timezone, preferences } })).data); }, "Settings saved.");
  }
  async function deleteAccount() {
    if (!confirmDelete) return;
    await act(async () => { await apiRequest("/me", { method: "DELETE", body: { confirm: "DELETE" } }); clearSession(); router.push("/signin"); }, "Account deleted.");
  }
  const csvMappingErrors = csvPreview ? [...csvPreview.errors, ...(!csvMapping.title ? ["Choose a column for the required title field."] : csvPreview.rows.flatMap((row, index) => { const i = csvPreview.headers.indexOf(csvMapping.title); return i >= 0 && !row[i]?.trim() ? [`Row ${index + 2}: mapped title is required.`] : []; }))] : [];
  const currentReview = reviews.find((r) => r.id === reviewId);
  const activeStages = useMemo(() => currentReview?.stages.filter((stage) => !stage.archived) ?? [], [currentReview]);
  const columns = useMemo(() => activeStages.map((stage) => ({ stage, rows: items.filter((item) => item.stage_id === stage.id) })), [activeStages, items]);

  return <div className="page-content research-workbench">
    <div className="page-heading"><div><p className="eyebrow">Research workspace</p><h1>Keep the evidence, methods, and next steps together.</h1><p className="page-lede">Research records are stored with your project. OmniAssist never runs code from an analysis record.</p></div></div>
    {error && <div className="notice notice-error" role="alert">{error}</div>}{notice && <div className="notice" role="status">{notice}</div>}
    <div className="research-controls"><label htmlFor="research-project">Project</label><select id="research-project" value={projectId} onChange={(e) => { setProjectId(e.target.value); setReviewId(""); setSelected(""); }}>{projects.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select><nav className="research-tabs" aria-label="Research tools">{tabs.map((item) => <button key={item.id} type="button" className={tab === item.id ? "active" : ""} onClick={() => { setTab(item.id); setError(""); setNotice(""); if (item.id === "notifications") void loadNotifications(); if (item.id === "settings") void loadProfile(); }}>{item.label}</button>)}</nav></div>
    {!projectId && tab !== "settings" && tab !== "notifications" && tab !== "exports" && <section className="panel"><h2>Create a project to begin.</h2><p>Research tools are organized by project.</p></section>}

    {tab === "reviews" && <section className="panel research-panel"><div className="panel-heading"><div><p className="eyebrow">Systematic review</p><h2>{currentReview?.name ?? "Review board"}</h2></div><button className="button button-secondary" type="button" onClick={downloadReviewCsv} disabled={!currentReview}>Export CSV</button></div>
      <div className="research-toolbar"><label htmlFor="review-select">Review</label><select id="review-select" value={reviewId} onChange={async (e) => { setReviewId(e.target.value); if (e.target.value) setItems((await apiRequest<ResearchItem[]>(`/reviews/${e.target.value}/items`)).data); }}><option value="">Choose a review</option>{reviews.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}</select><form className="inline-form" onSubmit={createReview}><label className="sr-only" htmlFor="new-review">New review name</label><input id="new-review" value={reviewName} onChange={(e) => setReviewName(e.target.value)} placeholder="New review name" required /><button className="button button-primary" disabled={busy}>Create review</button></form></div>
      {currentReview && <><details className="stage-editor"><summary>Edit review stages</summary><div>{currentReview.stages.map((stage) => <div className="stage-editor-row" key={stage.id}><label>{stage.name}<input aria-label={`Rename ${stage.name} stage`} defaultValue={stage.name} onBlur={(e) => { const name = e.target.value.trim(); if (name && name !== stage.name) void saveStages(currentReview.stages.map((candidate) => candidate.id === stage.id ? { ...candidate, name } : candidate)); }} /></label><button type="button" className="text-button" disabled={stage.archived} onClick={() => void saveStages(currentReview.stages.map((candidate) => candidate.id === stage.id ? { ...candidate, archived: true } : candidate))}>Archive</button></div>)}<form className="inline-form" onSubmit={(e) => { e.preventDefault(); const name = stageName.trim(); if (!name) return; void saveStages([...currentReview.stages, { id: newId(), name, archived: false }]); setStageName(""); }}><label className="sr-only" htmlFor="new-stage-name">New stage name</label><input id="new-stage-name" value={stageName} onChange={(e) => setStageName(e.target.value)} placeholder="Add a stage" /><button type="submit" className="button button-secondary">Add stage</button></form></div></details><form className="inline-form" onSubmit={createItem}><label className="sr-only" htmlFor="new-review-item">Citation or study title</label><input id="new-review-item" value={itemTitle} onChange={(e) => setItemTitle(e.target.value)} placeholder="Add a study or citation" required /><button className="button button-primary" disabled={busy}>Add item</button><label className="button button-secondary file-button">Preview CSV<input type="file" accept=".csv,text/csv" onChange={async (e: ChangeEvent<HTMLInputElement>) => { const file = e.target.files?.[0]; if (file) { const result = previewCsv(await file.text()); setCsvPreview(result); setCsvMapping({ title: result.headers.find((h) => h.toLowerCase() === "title") ?? result.headers[0] ?? "", source_identifier: result.headers.find((h) => ["source_identifier", "doi", "id"].includes(h.toLowerCase())) ?? "", notes: result.headers.find((h) => h.toLowerCase() === "notes") ?? "" }); } }} /></label></form>
      {csvPreview && <div className="csv-preview" aria-live="polite"><h3>Import preview</h3><p>{csvPreview.rows.length} data rows · {csvPreview.headers.join(" · ")} · limits: 1 MB, 100 rows, 50 columns</p>{csvPreview.headers.length > 0 && <div className="form-row">{(["title", "source_identifier", "notes"] as const).map((field) => <label key={field}>{field === "title" ? "Title (required)" : field.replaceAll("_", " ")}<select value={csvMapping[field]} onChange={(e) => setCsvMapping({ ...csvMapping, [field]: e.target.value })}><option value="">Do not import</option>{csvPreview.headers.map((header) => <option key={header}>{header}</option>)}</select></label>)}</div>}{csvMappingErrors.length > 0 ? <ul>{csvMappingErrors.slice(0, 30).map((e) => <li key={e}>{e}</li>)}</ul> : <button className="button button-primary" type="button" onClick={() => void importCsv()} disabled={busy}>Import {csvPreview.rows.length} rows</button>}<button className="button button-secondary" type="button" onClick={() => setCsvPreview(null)}>Cancel</button></div>}
      <div className="review-board">{columns.map(({ stage, rows }) => <section className="review-column" key={stage.id}><h3>{stage.name}<span>{rows.length}</span></h3>{rows.map((item) => <article className="research-card" key={item.id}><button type="button" className="research-item-title" onClick={() => setSelected(selected === item.id ? "" : item.id)}>{item.title}</button>{selected === item.id && <div><p>{String(item.notes ?? "No notes yet.")}</p><button type="button" className="text-button" onClick={async () => { const history = (await apiRequest<Row[]>(`/review-items/${item.id}/history`)).data; setNotice(history.length ? `History: ${history.map((h) => `${String(h.from_stage ?? "start")} → ${String(h.to_stage ?? "stage")} at ${String(h.created_at)}`).join("; ")}` : "No stage moves recorded yet."); }}>View stage history</button></div>}<label className="sr-only" htmlFor={`stage-${item.id}`}>Move {item.title} to stage</label><select id={`stage-${item.id}`} value={item.stage_id ?? ""} onChange={(e) => void moveItem(item, e.target.value)}>{activeStages.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select><small>{item.decision ? `Decision: ${String(item.decision)}` : "No decision"}</small></article>)}</section>)}</div></>}
    </section>}

    {tab === "analysis" && <section className="panel research-panel"><div className="panel-heading"><div><p className="eyebrow">R / Python ledger</p><h2>Analysis records</h2></div></div><p className="inline-note">Record runs and results; code is never executed by OmniAssist.</p><form className="research-form" onSubmit={createAnalysis}><label>Title<input value={recordTitle} onChange={(e) => setRecordTitle(e.target.value)} required /></label><label>Purpose<textarea value={analysisForm.purpose} onChange={(e) => setAnalysisForm({ ...analysisForm, purpose: e.target.value })} /></label><div className="form-row"><label>Language<select value={analysisForm.language} onChange={(e) => setAnalysisForm({ ...analysisForm, language: e.target.value })}><option value="python">Python</option><option value="r">R</option></select></label><label>Repository URL<input type="url" value={analysisForm.repository_url} onChange={(e) => setAnalysisForm({ ...analysisForm, repository_url: e.target.value })} /></label><label>Branch<input value={analysisForm.branch_name} onChange={(e) => setAnalysisForm({ ...analysisForm, branch_name: e.target.value })} /></label><label>Commit reference<input value={analysisForm.commit_ref} onChange={(e) => setAnalysisForm({ ...analysisForm, commit_ref: e.target.value })} /></label></div><div className="form-row"><label>Data source<input value={analysisForm.data_source_ref} onChange={(e) => setAnalysisForm({ ...analysisForm, data_source_ref: e.target.value })} /></label><label>Environment<textarea value={analysisForm.environment} onChange={(e) => setAnalysisForm({ ...analysisForm, environment: e.target.value })} /></label><label>Result summary<textarea value={analysisForm.result_summary} onChange={(e) => setAnalysisForm({ ...analysisForm, result_summary: e.target.value })} /></label><label>Error details<textarea value={analysisForm.error_details} onChange={(e) => setAnalysisForm({ ...analysisForm, error_details: e.target.value })} /></label><label>Next action<input value={analysisForm.next_action} onChange={(e) => setAnalysisForm({ ...analysisForm, next_action: e.target.value })} /></label></div><button className="button button-primary" disabled={busy}>Add analysis</button></form>
      <div className="record-list">{analyses.map((row) => <article className="research-record" key={row.id}><div className="panel-heading"><h3>{row.title}</h3><label>Status<select value={String(row.status ?? "planned")} onChange={(e) => void updateAnalysis(row, "status", e.target.value)}>{["planned", "running", "succeeded", "failed", "blocked", "archived"].map((s) => <option key={s}>{s}</option>)}</select></label></div><p>{String(row.purpose ?? "No purpose recorded.")}</p><form className="research-form" onSubmit={(e) => { e.preventDefault(); const values = Object.fromEntries(new FormData(e.currentTarget).entries()); void act(() => push("analysis_record", row.id, "update", { ...values, language: values.language || null, repository_url: values.repository_url || null }, row.version), "Analysis fields saved."); }}><div className="form-row"><label>Title<input name="title" required defaultValue={row.title} /></label>{["purpose", "repository_url", "branch_name", "commit_ref", "data_source_ref", "environment", "result_summary", "error_details", "next_action"].map((field) => <label key={field}>{field.replaceAll("_", " ")}{["purpose", "environment", "result_summary", "error_details", "next_action"].includes(field) ? <textarea name={field} defaultValue={String(row[field] ?? "")} /> : <input name={field} type={field === "repository_url" ? "url" : "text"} defaultValue={String(row[field] ?? "")} />}</label>)}<label>Language<select name="language" defaultValue={String(row.language ?? "")}><option value="">Not set</option><option value="python">Python</option><option value="r">R</option></select></label></div><button className="button button-secondary">Save analysis fields</button></form>{typeof row.next_action === "string" && row.next_action && <button className="button button-secondary" type="button" onClick={() => void addNextAction(row)}>Create next-action task: {row.next_action}</button>}</article>)}</div>
    </section>}

    {tab === "experiments" && <section className="panel research-panel"><div className="panel-heading"><div><p className="eyebrow">Lab record</p><h2>Timestamped experiment log</h2></div></div><p className="notice notice-warning">OmniAssist is not a validated regulated electronic lab notebook. Keep regulated records in your approved system.</p><form className="research-form" onSubmit={createExperiment}><div className="form-row"><label>Title<input value={experimentForm.title} onChange={(e) => setExperimentForm({ ...experimentForm, title: e.target.value })} required /></label><label>Occurred at<input type="datetime-local" value={experimentForm.occurred_at} onChange={(e) => setExperimentForm({ ...experimentForm, occurred_at: e.target.value })} required /></label><label>Template<select value={experimentForm.template_type} onChange={(e) => { const type = e.target.value; setExperimentForm({ ...experimentForm, template_type: type, objective: type === "qpcr" ? "Measure target and reference gene expression." : type === "primer_design" ? "Design and validate primers for the target sequence." : experimentForm.objective, protocol: type === "qpcr" ? "Record sample preparation, reaction setup, cycling conditions, and controls." : type === "primer_design" ? "Record target sequence, design parameters, specificity checks, and validation plan." : experimentForm.protocol, variables: type === "qpcr" ? "Target, reference gene, biological and technical replicates." : type === "primer_design" ? "Forward/reverse sequence, Tm, GC content, amplicon length." : experimentForm.variables }); }}><option value="">General</option><option value="qpcr">qPCR</option><option value="primer_design">Primer design</option></select></label></div>{["objective", "protocol", "variables", "materials", "observations", "deviations", "result_summary", "next_steps"].map((field) => <label key={field}>{field.replaceAll("_", " ")}<textarea maxLength={50000} value={experimentForm[field]} onChange={(e) => setExperimentForm({ ...experimentForm, [field]: e.target.value })} /></label>)}<button className="button button-primary" disabled={busy}>Save draft</button></form><div className="record-list">{experiments.map((row) => <article className="research-record" key={row.id}><div className="panel-heading"><div><h3>{row.title}</h3><small>{String(row.occurred_at ?? "")} · {row.state === "finalized" ? `Finalized · revision ${String(row.revision_number ?? 1)}` : "Draft"}</small></div>{row.state !== "finalized" && <button className="button button-secondary" onClick={() => void finalizeExperiment(row)} type="button">Finalize</button>}</div><details><summary>View entry details</summary><dl className="record-details">{["objective", "protocol", "variables", "materials", "observations", "deviations", "result_summary", "next_steps"].map((field) => <div key={field}><dt>{field.replaceAll("_", " ")}</dt><dd>{String(row[field] ?? "—")}</dd></div>)}</dl></details>{row.state !== "finalized" && <form className="research-form" onSubmit={(e) => { e.preventDefault(); const values = Object.fromEntries(new FormData(e.currentTarget).entries()); void saveExperiment(row, values); }}><label>Title<input name="title" required defaultValue={row.title} /></label>{["objective", "protocol", "variables", "materials", "observations", "deviations", "result_summary", "next_steps"].map((field) => <label key={field}>{field.replaceAll("_", " ")}<textarea name={field} maxLength={50000} defaultValue={String(row[field] ?? "")} /></label>)}<button className="button button-secondary">Save draft fields</button></form>}<button type="button" className="text-button" onClick={async () => { const revisions = (await apiRequest<Row[]>(`/experiment-entries/${row.id}/revisions`)).data; setNotice(`${revisions.length} preserved revision(s) for ${row.title}.`); }}>View revisions</button></article>)}</div></section>}

    {tab === "search" && <section className="panel research-panel"><p className="eyebrow">Find your work</p><h2>Search this workspace</h2><form className="inline-form" onSubmit={runSearch}><label className="sr-only" htmlFor="research-search">Search term</label><input id="research-search" value={searchText} onChange={(e) => setSearchText(e.target.value)} placeholder="Search titles, notes, identifiers…" required /><label className="sr-only" htmlFor="search-type">Filter by record type</label><select id="search-type" value={searchType} onChange={(e) => setSearchType(e.target.value)}><option value="">All record types</option><option value="task">Tasks</option><option value="project">Projects</option><option value="milestone">Milestones</option><option value="review_item">Review items</option><option value="analysis_record">Analyses</option><option value="experiment_entry">Experiments</option></select><button className="button button-primary">Search</button></form>{searchResults.length ? <ul className="search-results">{searchResults.map((r) => <li key={`${r.entity_type}-${r.id}`}><b>{r.title}</b><span>{r.entity_type.replaceAll("_", " ")} · {r.status ?? "active"}</span></li>)}</ul> : <p className="empty-state">Search is scoped to your authorized workspace. Enter a term to find matching records.</p>}</section>}

    {tab === "notifications" && <section className="panel research-panel"><div className="panel-heading"><div><p className="eyebrow">Reminder history</p><h2>Notifications</h2></div><button type="button" className="button button-secondary" onClick={() => void loadNotifications()}>Refresh</button></div><div className="notification-list">{notifications.length ? notifications.map((n) => <article className="research-record" key={n.id}><div className="panel-heading"><h3>{n.title}</h3><span className="status-badge">{n.delivery_status}</span></div>{n.scheduled_at && <p>{new Date(n.scheduled_at).toLocaleString()}</p>}<div className="inline-form"><button type="button" className="button button-secondary" onClick={() => void notificationAction(n.id, "read")}>Mark read</button><button type="button" className="button button-secondary" onClick={() => void notificationAction(n.id, "ack")}>Acknowledge</button><button type="button" className="button button-secondary" onClick={() => void notificationAction(n.id, "dismiss")}>Dismiss</button></div></article>) : <div className="empty-state">No notification history yet.</div>}</div></section>}

    {tab === "exports" && <section className="panel research-panel"><p className="eyebrow">Take your data with you</p><h2>Workspace exports</h2><p>Exports run in the background. Download links are signed and expire automatically.</p><div className="inline-form"><button className="button button-primary" type="button" disabled={busy} onClick={() => void requestExport("json")}>Request JSON export</button><button className="button button-secondary" type="button" disabled={busy} onClick={() => void requestExport("csv")}>Request CSV export</button></div><div className="record-list">{exports.map((job) => <article className="research-record" key={job.id}><div className="panel-heading"><b>{job.format.toUpperCase()} export</b><span>{job.status}</span></div>{job.download_url && <a className="button button-primary" href={apiUrl(job.download_url)} target="_blank" rel="noreferrer">Download export</a>}{job.expires_at && <small>Expires {new Date(job.expires_at).toLocaleString()}</small>}<button className="text-button" type="button" onClick={() => void pollExport(job.id)}>Refresh status</button></article>)}</div></section>}

    {tab === "settings" && <section className="panel research-panel"><p className="eyebrow">Your account</p><h2>Preferences and privacy</h2>{profile && <form className="research-form" onSubmit={saveProfile}><label>Display name<input value={profile.display_name ?? ""} onChange={(e) => setProfile({ ...profile, display_name: e.target.value })} /></label><label>Timezone<input value={profile.timezone ?? "UTC"} onChange={(e) => setProfile({ ...profile, timezone: e.target.value })} placeholder="Europe/London" /></label><fieldset className="quiet-hours"><legend>Quiet hours</legend><label>Start<input type="time" value={quietStart} onChange={(e) => setQuietStart(e.target.value)} /></label><label>End<input type="time" value={quietEnd} onChange={(e) => setQuietEnd(e.target.value)} /></label><small>Non-critical reminders wait until quiet hours end.</small></fieldset><button className="button button-primary">Save preferences</button></form>}<div className="danger-zone"><h3>Delete account</h3><p>This permanently deletes your account and workspace data. This cannot be undone.</p><label className="confirm-check"><input type="checkbox" checked={confirmDelete} onChange={(e) => setConfirmDelete(e.target.checked)} /> I understand that account deletion is permanent.</label><button type="button" className="button button-danger" disabled={!confirmDelete || busy} onClick={() => void deleteAccount()}>Permanently delete my account</button></div></section>}
  </div>;
}
