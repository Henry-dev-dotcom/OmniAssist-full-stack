import { previewCsv } from "@/lib/research/csv";
import {
  CHECKLIST, STATUSES, STEPS, blankDraft, type ChecklistStep, type Scholarship, type ScholarshipDraft,
  type ScholarshipStatus,
} from "./types";

const FIELDS = [
  "region", "university", "program", "scheme", "portal_link", "opens_label", "deadline", "status",
  "documents_required", "cv_status", "transcripts_status", "letter_status", "references_status",
  "portal_status", "funding", "notes",
] as const;

// A leading = + - @ would run as a formula when the file is opened in a spreadsheet.
function cell(value: unknown): string {
  let text = typeof value === "string" ? value : "";
  if (/^[=+\-@]/.test(text)) text = `'${text}`;
  return /[",\n\r]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

export function scholarshipsToCsv(items: Scholarship[]): string {
  const lines: string[] = [FIELDS.join(",")];
  for (const item of items) {
    const row: Record<string, unknown> = { ...item, deadline: item.deadline_at ? item.deadline_at.slice(0, 10) : null };
    lines.push(FIELDS.map((field) => cell(row[field])).join(","));
  }
  return `﻿${lines.join("\r\n")}`;
}

export type CsvImport = { drafts: ScholarshipDraft[]; errors: string[] };

/** Reads a CSV made by scholarshipsToCsv. Rows with a problem are reported and left out. */
export function scholarshipsFromCsv(source: string): CsvImport {
  const preview = previewCsv(source.replace(/^﻿/, ""));
  if (preview.errors.length) return { drafts: [], errors: preview.errors };
  const index = new Map(preview.headers.map((header, i) => [header.toLowerCase(), i]));
  if (!index.has("university") || !index.has("region")) {
    return { drafts: [], errors: ["The CSV needs region and university columns. Use a file exported from this page."] };
  }
  const drafts: ScholarshipDraft[] = [];
  const errors: string[] = [];
  preview.rows.forEach((values, n) => {
    const get = (field: string) => (values[index.get(field) ?? -1] ?? "").replace(/^'(?=[=+\-@])/, "").trim();
    const row = `Row ${n + 2}`;
    const draft = blankDraft(get("region"));
    for (const field of ["program", "scheme", "portal_link", "opens_label", "documents_required", "funding", "notes"] as const) {
      draft[field] = get(field) || null;
    }
    draft.university = get("university");
    if (!draft.region || !draft.university) { errors.push(`${row}: region and university are required.`); return; }
    if (draft.portal_link && !/^https?:\/\//i.test(draft.portal_link)) { errors.push(`${row}: portal_link must start with http:// or https://.`); return; }
    const deadline = get("deadline");
    if (deadline && !/^\d{4}-\d{2}-\d{2}$/.test(deadline)) { errors.push(`${row}: deadline must be YYYY-MM-DD.`); return; }
    draft.deadline = deadline || null;
    const status = (get("status") || "not_started") as ScholarshipStatus;
    if (!STATUSES.includes(status)) { errors.push(`${row}: unknown status "${status}".`); return; }
    draft.status = status;
    for (const { key } of CHECKLIST) {
      const step = (get(key) || "not_started") as ChecklistStep;
      if (!STEPS.includes(step)) { errors.push(`${row}: unknown ${key} "${step}".`); return; }
      draft[key] = step;
    }
    drafts.push(draft);
  });
  return { drafts, errors };
}
