export type ScholarshipStatus =
  | "not_started" | "preparing" | "submitted" | "under_review" | "accepted" | "rejected";
export type ChecklistStep =
  | "not_started" | "in_progress" | "requested" | "registered" | "pending" | "ready" | "submitted";

export const STATUSES: ScholarshipStatus[] = [
  "not_started", "preparing", "submitted", "under_review", "accepted", "rejected",
];
export const STEPS: ChecklistStep[] = [
  "not_started", "in_progress", "requested", "registered", "pending", "ready", "submitted",
];

export const CHECKLIST = [
  { key: "cv_status", label: "CV" },
  { key: "transcripts_status", label: "Transcripts" },
  { key: "letter_status", label: "Motivation letter / SOP" },
  { key: "references_status", label: "References" },
  { key: "portal_status", label: "Portal registration" },
] as const;
export type ChecklistKey = (typeof CHECKLIST)[number]["key"];

type Stored = { id: string; workspace_id: string; version: number; updated_at: string };

/** A group of applications: a country, a degree level, or anything else the user names. */
export type SectionDraft = { name: string; description: string | null };
export type Section = SectionDraft & Stored & { position: number };

/** A funding route within a section (a government quota, an olympiad, a merit award). */
export type SchemeDraft = {
  name: string;
  organizing_body: string | null;
  coverage: string | null;
  strategy: string | null;
};
export type Scheme = SchemeDraft & Stored & { section_id: string; position: number };

/** The form and starter-list shape: the deadline is a plain date (YYYY-MM-DD) or null. */
export type ScholarshipDraft = {
  university: string;
  program: string | null;
  scheme: string | null;
  portal_link: string | null;
  opens_label: string | null;
  deadline: string | null;
  status: ScholarshipStatus;
  documents_required: string | null;
  cv_status: ChecklistStep;
  transcripts_status: ChecklistStep;
  letter_status: ChecklistStep;
  references_status: ChecklistStep;
  portal_status: ChecklistStep;
  funding: string | null;
  notes: string | null;
};

/** A stored application as the API returns it. */
export type Scholarship = Omit<ScholarshipDraft, "deadline"> & Stored & {
  section_id: string;
  deadline_at: string | null;
};

/** One sheet of the original tracker, ready to be added as a section. */
export type StarterSection = SectionDraft & { schemes: SchemeDraft[]; applications: ScholarshipDraft[] };

export const label = (value: string) =>
  value.replaceAll("_", " ").replace(/\b\w/g, (c) => c.toUpperCase());

export function blankDraft(): ScholarshipDraft {
  return {
    university: "", program: null, scheme: null, portal_link: null, opens_label: null,
    deadline: null, status: "not_started", documents_required: null, cv_status: "not_started",
    transcripts_status: "not_started", letter_status: "not_started", references_status: "not_started",
    portal_status: "not_started", funding: null, notes: null,
  };
}

export function draftFromScholarship(item: Scholarship): ScholarshipDraft {
  return {
    university: item.university, program: item.program, scheme: item.scheme,
    portal_link: item.portal_link, opens_label: item.opens_label,
    deadline: item.deadline_at ? item.deadline_at.slice(0, 10) : null, status: item.status,
    documents_required: item.documents_required, cv_status: item.cv_status,
    transcripts_status: item.transcripts_status, letter_status: item.letter_status,
    references_status: item.references_status, portal_status: item.portal_status,
    funding: item.funding, notes: item.notes,
  };
}

export const blankToNull = (value: string | null) => (value && value.trim() ? value.trim() : null);

/** Converts an application draft to the field set the API accepts. */
export function toChanges(draft: ScholarshipDraft, sectionId: string): Record<string, unknown> {
  const { deadline, ...rest } = draft;
  return {
    ...rest,
    section_id: sectionId,
    university: draft.university.trim(),
    program: blankToNull(draft.program),
    scheme: blankToNull(draft.scheme),
    portal_link: blankToNull(draft.portal_link),
    opens_label: blankToNull(draft.opens_label),
    documents_required: blankToNull(draft.documents_required),
    funding: blankToNull(draft.funding),
    notes: blankToNull(draft.notes),
    deadline_at: deadline ? `${deadline}T00:00:00Z` : null,
  };
}

export function schemeChanges(draft: SchemeDraft, sectionId: string): Record<string, unknown> {
  return {
    section_id: sectionId,
    name: draft.name.trim(),
    organizing_body: blankToNull(draft.organizing_body),
    coverage: blankToNull(draft.coverage),
    strategy: blankToNull(draft.strategy),
  };
}

export function sectionChanges(draft: SectionDraft): Record<string, unknown> {
  return { name: draft.name.trim(), description: blankToNull(draft.description) };
}

const DONE: ChecklistStep[] = ["ready", "submitted", "registered"];

/** Share of the five checklist steps that are done, 0-100. */
export function checklistProgress(item: Pick<Scholarship, ChecklistKey>): number {
  return Math.round((CHECKLIST.filter(({ key }) => DONE.includes(item[key])).length / CHECKLIST.length) * 100);
}

/** Whole days from today (UTC) to the deadline; null when there is none. */
export function daysUntil(deadlineAt: string | null, now = new Date()): number | null {
  if (!deadlineAt) return null;
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const target = new Date(deadlineAt);
  return Math.round((Date.UTC(target.getUTCFullYear(), target.getUTCMonth(), target.getUTCDate()) - today) / 86_400_000);
}

export const CLOSED: ScholarshipStatus[] = ["submitted", "under_review", "accepted", "rejected"];

export const sameName = (a: string, b: string) => a.trim().toLowerCase() === b.trim().toLowerCase();
