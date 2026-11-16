import { apiRequest } from "@/lib/api/client";
import {
  draftFromScholarship, schemeChanges, sectionChanges, toChanges,
  type Scholarship, type Scheme, type Section, type StarterSection,
} from "./types";

const PAGE = 100;
const BATCH = 50;

async function listAll<T>(path: string, workspaceId: string): Promise<T[]> {
  const all: T[] = [];
  for (let offset = 0; ; offset += PAGE) {
    const page = await apiRequest<T[]>(`${path}?workspace_id=${workspaceId}&limit=${PAGE}&offset=${offset}`);
    all.push(...page.data);
    if (page.data.length < PAGE) return all;
  }
}

export async function loadTracker(workspaceId: string) {
  const [sections, schemes, applications] = await Promise.all([
    listAll<Section>("/scholarship-sections", workspaceId),
    listAll<Scheme>("/scholarship-schemes", workspaceId),
    listAll<Scholarship>("/scholarship-applications", workspaceId),
  ]);
  return { sections, schemes, applications };
}

export type EntityType = "scholarship_section" | "scholarship_scheme" | "scholarship_application";
export type Change = {
  entity: EntityType;
  id: string;
  operation: "create" | "update" | "delete";
  changes?: Record<string, unknown>;
  baseVersion?: number;
};

type PushResult = { status: string; message?: string; error_code?: string };

/**
 * Sends changes in order, in batches. The server applies them in the order given, so a section
 * can be followed by the records that belong to it. Resolves with how many were accepted and
 * the first rejection message, if any.
 */
export async function pushChanges(workspaceId: string, items: Change[]) {
  let accepted = 0;
  let firstError: string | null = null;
  for (let i = 0; i < items.length; i += BATCH) {
    const response = await apiRequest<{ results: PushResult[] }>("/sync/push", {
      method: "POST",
      body: {
        device_id: crypto.randomUUID(),
        protocol_version: 1,
        cursor: 0,
        mutations: items.slice(i, i + BATCH).map((item) => ({
          mutation_id: crypto.randomUUID(),
          workspace_id: workspaceId,
          entity_type: item.entity,
          entity_id: item.id,
          operation: item.operation,
          base_version: item.baseVersion,
          changes: item.changes ?? {},
        })),
      },
    });
    for (const result of response.data.results) {
      if (result.status === "accepted") accepted += 1;
      else firstError ??= result.message ?? `Rejected (${result.error_code ?? "unknown error"}).`;
    }
  }
  return { accepted, rejected: items.length - accepted, firstError };
}

/** A starter section with its schemes and applications, section first. */
export function starterChanges(starter: StarterSection, position: number): Change[] {
  const sectionId = crypto.randomUUID();
  return [
    { entity: "scholarship_section", id: sectionId, operation: "create", changes: { ...sectionChanges(starter), position } },
    ...starter.schemes.map((scheme, index): Change => ({
      entity: "scholarship_scheme", id: crypto.randomUUID(), operation: "create",
      changes: { ...schemeChanges(scheme, sectionId), position: index },
    })),
    ...starter.applications.map((draft): Change => ({
      entity: "scholarship_application", id: crypto.randomUUID(), operation: "create",
      changes: toChanges(draft, sectionId),
    })),
  ];
}

/** Everything in a section, then the section itself (the server refuses a section with contents). */
export function removeSectionChanges(section: Section, schemes: Scheme[], applications: Scholarship[]): Change[] {
  return [
    ...applications.filter((a) => a.section_id === section.id)
      .map((a): Change => ({ entity: "scholarship_application", id: a.id, operation: "delete", baseVersion: a.version })),
    ...schemes.filter((s) => s.section_id === section.id)
      .map((s): Change => ({ entity: "scholarship_scheme", id: s.id, operation: "delete", baseVersion: s.version })),
    { entity: "scholarship_section", id: section.id, operation: "delete", baseVersion: section.version },
  ];
}

/** Re-creates a deleted application as a new record (a deleted record's id cannot be reused). */
export function restoreApplicationChange(item: Scholarship, sectionId = item.section_id): Change {
  return { entity: "scholarship_application", id: crypto.randomUUID(), operation: "create", changes: toChanges(draftFromScholarship(item), sectionId) };
}

/** Re-creates a deleted scheme as a new record. */
export function restoreSchemeChange(scheme: Scheme, sectionId = scheme.section_id): Change {
  return { entity: "scholarship_scheme", id: crypto.randomUUID(), operation: "create", changes: { ...schemeChanges(scheme, sectionId), position: scheme.position } };
}

/** Re-creates a removed section with everything that was in it, section first. */
export function restoreSectionChanges(section: Section, schemes: Scheme[], applications: Scholarship[]): Change[] {
  const sectionId = crypto.randomUUID();
  return [
    { entity: "scholarship_section", id: sectionId, operation: "create", changes: { ...sectionChanges(section), position: section.position } },
    ...schemes.filter((s) => s.section_id === section.id).map((s) => restoreSchemeChange(s, sectionId)),
    ...applications.filter((a) => a.section_id === section.id).map((a) => restoreApplicationChange(a, sectionId)),
  ];
}
