"use client";

import { useState } from "react";
import { choiceFor, type ReminderChoice } from "@/lib/reminders";

/**
 * A compact "Remind me" control for a dated record. It shows the current choice and saves a new
 * one straight away; the parent supplies how to save. Reminders arrive in the app's
 * notification bell and, when turned on for the device, as notifications.
 */
export function ReminderPicker({ label, choices, current, disabled, onChange }: {
  label: string;
  choices: ReminderChoice[];
  current: string[];
  disabled?: boolean;
  onChange: (offsets: string[]) => Promise<string | void>;
}) {
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");
  const selected = choiceFor(choices, current);
  const options = selected.id === "custom" ? [...choices, selected] : choices;

  async function pick(id: string) {
    const choice = options.find((c) => c.id === id);
    if (!choice) return;
    setSaving(true);
    setMessage("");
    try {
      setMessage((await onChange(choice.offsets)) || "");
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "The reminder could not be saved.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <label className="reminder-picker">
      <span>{current.length ? "Reminder" : "Remind me"}</span>
      <select value={selected.id} disabled={disabled || saving} onChange={(e) => void pick(e.target.value)} aria-label={label}>
        {options.map((c) => <option key={c.id} value={c.id}>{c.label}</option>)}
      </select>
      {message && <small role="status">{message}</small>}
    </label>
  );
}
