/** "in_progress" → "In progress". For status and type values that come straight from the API. */
export function humanize(value: string | null | undefined) {
  if (!value) return "";
  const words = value.replaceAll("_", " ").trim();
  return words.charAt(0).toUpperCase() + words.slice(1).toLowerCase();
}

/** A local date and time, for timestamps the API sends in UTC. */
export function formatDateTime(iso: string | null | undefined) {
  if (!iso) return "";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}

/** The current local time as a value for an `<input type="datetime-local">`. */
export function nowForInput() {
  const now = new Date();
  now.setSeconds(0, 0);
  return new Date(now.getTime() - now.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
}
