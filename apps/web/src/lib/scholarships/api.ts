import { apiRequest } from "@/lib/api/client";
import type { Scholarship } from "./types";

const PAGE = 100;
const BATCH = 50;

export async function listScholarships(workspaceId: string): Promise<Scholarship[]> {
  const all: Scholarship[] = [];
  for (let offset = 0; ; offset += PAGE) {
    const page = await apiRequest<Scholarship[]>(
      `/scholarship-applications?workspace_id=${workspaceId}&limit=${PAGE}&offset=${offset}`,
    );
    all.push(...page.data);
    if (page.data.length < PAGE) return all;
  }
}

export type Change = {
  id: string;
  operation: "create" | "update" | "delete";
  changes?: Record<string, unknown>;
  baseVersion?: number;
};

type PushResult = { status: string; message?: string; error_code?: string };

/** Sends changes in batches. Resolves with how many were accepted and the first rejection message, if any. */
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
          entity_type: "scholarship_application",
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
