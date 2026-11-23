"use client";

import { useCallback, useEffect, useState } from "react";
import { apiRequest } from "@/lib/api/client";

export type ReminderEntity = "funding_opportunity" | "scholarship_application" | "milestone" | "time_block";

export type ScheduledReminder = {
  id: string;
  entity_type: string;
  entity_id: string;
  title: string;
  remind_at: string;
  offset_spec: string | null;
  delivery_status: string;
};

export type ReminderChoice = { id: string; label: string; offsets: string[] };

// Deadlines and due dates: morning reminders use 09:00 in the user's time zone (see the API).
export const DEADLINE_CHOICES: ReminderChoice[] = [
  { id: "off", label: "No reminder", offsets: [] },
  { id: "morning_of", label: "Morning of the day", offsets: ["morning_of"] },
  { id: "morning_before", label: "Day before", offsets: ["morning_before"] },
  { id: "3d", label: "3 days before", offsets: ["custom:4320"] },
  { id: "1w", label: "1 week before", offsets: ["custom:10080"] },
  { id: "1w+1d", label: "1 week and the day before", offsets: ["custom:10080", "morning_before"] },
];

export const START_CHOICES: ReminderChoice[] = [
  { id: "off", label: "No reminder", offsets: [] },
  { id: "at_due", label: "When it starts", offsets: ["at_due"] },
  { id: "15m", label: "15 minutes before", offsets: ["15m"] },
  { id: "1h", label: "1 hour before", offsets: ["1h"] },
];

const key = (type: string, id: string) => `${type}:${id}`;

/** The choice matching a record's current offsets, or a "Custom" one if they match none. */
export function choiceFor(choices: ReminderChoice[], offsets: string[]): ReminderChoice {
  const sorted = [...offsets].sort().join(",");
  return choices.find((c) => [...c.offsets].sort().join(",") === sorted)
    ?? { id: "custom", label: "Custom", offsets };
}

/** Scheduled reminders for the workspace, keyed by record, plus a way to change one record's. */
export function useReminders(workspaceId: string | undefined) {
  const [byRecord, setByRecord] = useState<Map<string, string[]>>(new Map());

  const refresh = useCallback(async () => {
    if (!workspaceId) return;
    try {
      const rows = (await apiRequest<ScheduledReminder[]>(`/reminders?workspace_id=${workspaceId}`)).data;
      const next = new Map<string, string[]>();
      for (const r of rows) {
        if (!r.offset_spec) continue;
        const k = key(r.entity_type, r.entity_id);
        next.set(k, [...(next.get(k) ?? []), r.offset_spec]);
      }
      setByRecord(next);
    } catch {
      // Reminders are an extra: the page still works without them.
    }
  }, [workspaceId]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void refresh(); }, [refresh]);

  const offsetsFor = useCallback((type: ReminderEntity, id: string) => byRecord.get(key(type, id)) ?? [], [byRecord]);

  /** Sets a record's reminders. Resolves with how many could not be scheduled (already past). */
  const setReminders = useCallback(async (type: ReminderEntity, id: string, offsets: string[]) => {
    const response = await apiRequest<ScheduledReminder[]>(`/reminders/${type}/${id}`, {
      method: "PUT",
      body: { offsets, channel: "push" },
    });
    await refresh();
    const warnings = (response.meta as { warnings?: { code: string; count: number }[] }).warnings ?? [];
    return warnings.find((w) => w.code === "REMINDER_IN_PAST")?.count ?? 0;
  }, [refresh]);

  return { offsetsFor, setReminders, refresh };
}
