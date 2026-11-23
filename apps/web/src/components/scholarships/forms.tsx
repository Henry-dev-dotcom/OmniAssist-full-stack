"use client";

import type { ChangeEvent, FormEvent, ReactNode } from "react";
import { useState } from "react";
import { useFormFocus } from "@/lib/use-form-focus";
import {
  CHECKLIST, STATUSES, STEPS, label,
  type ScholarshipDraft, type ScholarshipStatus, type SchemeDraft, type Section, type SectionDraft,
} from "@/lib/scholarships/types";

type Common = { busy: boolean; onCancel: () => void };

function Panel({ eyebrow, title, onCancel, children }: { eyebrow: string; title: string; onCancel: () => void; children: ReactNode }) {
  const ref = useFormFocus<HTMLElement>(true);
  return (
    <section ref={ref} className="panel grant-form-panel" aria-label={title}>
      <div className="panel-heading">
        <div><p className="eyebrow">{eyebrow}</p><h2>{title}</h2></div>
        <button className="button button-secondary" type="button" onClick={onCancel}>Cancel</button>
      </div>
      {children}
    </section>
  );
}

function Actions({ busy, submitLabel, onCancel }: Common & { submitLabel: string }) {
  return (
    <div className="grant-form-actions">
      <button className="button button-primary" type="submit" disabled={busy}>{busy ? "Saving…" : submitLabel}</button>
      <button className="button button-secondary" type="button" onClick={onCancel} disabled={busy}>Cancel</button>
    </div>
  );
}

const submit = (run: () => void) => (event: FormEvent<HTMLFormElement>) => { event.preventDefault(); run(); };

export function SectionForm({ initial, editing, busy, onCancel, onSubmit }: Common & {
  initial: SectionDraft; editing: boolean; onSubmit: (draft: SectionDraft) => void;
}) {
  const [draft, setDraft] = useState(initial);
  return (
    <Panel eyebrow="Section" title={editing ? "Edit section" : "New section"} onCancel={onCancel}>
      <form className="grant-form" onSubmit={submit(() => onSubmit(draft))}>
        <label>Section name<input required maxLength={80} value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} placeholder="e.g. Germany, UK PhD, Fellowships" /></label>
        <label>Description<textarea maxLength={2000} rows={2} value={draft.description ?? ""} onChange={(e) => setDraft({ ...draft, description: e.target.value || null })} placeholder="Target programs, degree level, or anything that defines this group" /></label>
        <Actions busy={busy} onCancel={onCancel} submitLabel={editing ? "Save section" : "Create section"} />
      </form>
    </Panel>
  );
}

export function SchemeForm({ initial, editing, busy, onCancel, onSubmit }: Common & {
  initial: SchemeDraft; editing: boolean; onSubmit: (draft: SchemeDraft) => void;
}) {
  const [draft, setDraft] = useState(initial);
  const text = (key: keyof SchemeDraft) => (e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
    setDraft({ ...draft, [key]: key === "name" ? e.target.value : e.target.value || null });
  return (
    <Panel eyebrow="Scholarship scheme" title={editing ? "Edit scheme" : "New scheme"} onCancel={onCancel}>
      <form className="grant-form" onSubmit={submit(() => onSubmit(draft))}>
        <div className="grant-form-grid">
          <label>Scheme name<input required maxLength={240} value={draft.name} onChange={text("name")} /></label>
          <label>Organizing body<input maxLength={500} value={draft.organizing_body ?? ""} onChange={text("organizing_body")} /></label>
        </div>
        <label>Key coverage<textarea maxLength={2000} rows={2} value={draft.coverage ?? ""} onChange={text("coverage")} placeholder="Tuition, stipend, insurance…" /></label>
        <label>Application strategy and next steps<textarea maxLength={5000} rows={3} value={draft.strategy ?? ""} onChange={text("strategy")} /></label>
        <Actions busy={busy} onCancel={onCancel} submitLabel={editing ? "Save scheme" : "Add scheme"} />
      </form>
    </Panel>
  );
}

type TextKey = "program" | "scheme" | "portal_link" | "opens_label" | "documents_required" | "funding" | "notes";

export function ApplicationForm({ initial, initialSectionId, sections, editing, busy, onCancel, onSubmit }: Common & {
  initial: ScholarshipDraft; initialSectionId: string; sections: Section[]; editing: boolean;
  onSubmit: (draft: ScholarshipDraft, sectionId: string) => void;
}) {
  const [draft, setDraft] = useState(initial);
  const [sectionId, setSectionId] = useState(initialSectionId);
  function set<K extends keyof ScholarshipDraft>(key: K, value: ScholarshipDraft[K]) {
    setDraft((current) => ({ ...current, [key]: value }));
  }
  const text = (key: TextKey) => (e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => set(key, e.target.value || null);
  return (
    <Panel eyebrow="Application details" title={editing ? "Edit application" : "New application"} onCancel={onCancel}>
      <form className="grant-form" onSubmit={submit(() => onSubmit(draft, sectionId))}>
        <div className="grant-form-grid">
          <label>University<input required maxLength={240} value={draft.university} onChange={(e) => set("university", e.target.value)} /></label>
          <label>Section<select required value={sectionId} onChange={(e) => setSectionId(e.target.value)}>{sections.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select></label>
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
        <label>Notes and follow-ups<textarea maxLength={20000} rows={4} value={draft.notes ?? ""} onChange={text("notes")} /></label>
        <Actions busy={busy} onCancel={onCancel} submitLabel={editing ? "Save changes" : "Add application"} />
      </form>
    </Panel>
  );
}
