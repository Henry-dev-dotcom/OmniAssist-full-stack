"use client";
import type { FormEvent } from "react";
import { useCallback, useEffect, useMemo, useState, useSyncExternalStore } from "react";
import { apiRequest } from "@/lib/api/client";
import type { TimeBlock, Workspace } from "@/lib/types/domain";
import { UndoBar } from "@/components/undo-bar";
import { useFormFocus } from "@/lib/use-form-focus";
import { ReminderPicker } from "@/components/reminder-picker";
import { START_CHOICES, useReminders } from "@/lib/reminders";

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const CATEGORIES = ["Focus", "Meeting", "Study", "Admin", "Break"];

// Today's date comes from the browser clock; the server renders without dates, so the two never disagree.
const noSubscribe = () => () => {};
const todayKey = () => new Date().toDateString();
const serverToday = () => null;

type BlockForm = { title: string; date: string; start: string; end: string; category: string; reminder: string };
type Overlap = { code: string; block_ids: string[] };

const pad = (n: number) => String(n).padStart(2, "0");
const dateInput = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const timeLabel = (iso: string) => new Date(iso).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });

function mondayOf(date: Date) {
  const monday = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7));
  return monday;
}

function weekTitle(offset: number, monday: Date | null) {
  if (offset === 0) return "This week";
  if (offset === 1) return "Next week";
  if (offset === -1) return "Last week";
  return monday ? `Week of ${monday.toLocaleDateString(undefined, { day: "numeric", month: "short" })}` : "This week";
}

export default function CalendarPage() {
  const [workspace, setWorkspace] = useState<Workspace | null>(null);
  const [blocks, setBlocks] = useState<TimeBlock[]>([]);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [offset, setOffset] = useState(0);
  const [form, setForm] = useState<BlockForm | null>(null);
  const [saving, setSaving] = useState(false);
  const [deleted, setDeleted] = useState<TimeBlock | null>(null);
  const today = useSyncExternalStore(noSubscribe, todayKey, serverToday);
  const formRef = useFormFocus<HTMLElement>(form ? "new" : null);
  const reminders = useReminders(workspace?.id);

  const monday = useMemo(() => {
    if (!today) return null;
    const start = mondayOf(new Date(today));
    start.setDate(start.getDate() + offset * 7);
    return start;
  }, [today, offset]);

  const load = useCallback(async () => {
    if (!monday) return;
    try {
      const ws = (await apiRequest<Workspace[]>("/workspaces")).data[0] ?? null;
      setWorkspace(ws);
      if (!ws) return;
      const end = new Date(monday);
      end.setDate(monday.getDate() + 7);
      const range = `start=${encodeURIComponent(monday.toISOString())}&end=${encodeURIComponent(end.toISOString())}`;
      setBlocks((await apiRequest<TimeBlock[]>(`/time-blocks?workspace_id=${ws.id}&${range}`)).data);
      setError("");
    } catch {
      setError("Calendar data is not available yet.");
    }
  }, [monday]);

  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void load(); }, [load]);

  const days = DAYS.map((label, index) => {
    if (!monday) return { label, date: null as Date | null };
    const date = new Date(monday);
    date.setDate(monday.getDate() + index);
    return { label, date };
  });
  const blocksOn = (date: Date | null) => (date
    ? blocks
      .filter((b) => new Date(b.starts_at).toDateString() === date.toDateString())
      .sort((a, b) => a.starts_at.localeCompare(b.starts_at))
    : []);

  function openForm() {
    const start = monday && offset !== 0 ? monday : new Date();
    // Today, suggest the next full hour rather than a 09:00 that may already be past.
    const hour = offset === 0 ? Math.min(Math.max(new Date().getHours() + 1, 9), 22) : 9;
    setForm({ title: "", date: dateInput(start), start: `${pad(hour)}:00`, end: `${pad(hour + 1)}:00`, category: "Focus", reminder: "off" });
    setError("");
    setNotice("");
  }

  async function create(values: { title: string; category: string; starts_at: string; ends_at: string }) {
    if (!workspace) throw new Error("No workspace is available for the calendar.");
    const response = await apiRequest<TimeBlock>("/time-blocks", {
      method: "POST",
      body: { workspace_id: workspace.id, status: "planned", ...values },
    });
    const overlaps = (response.meta as { warnings?: Overlap[] }).warnings ?? [];
    return { id: response.data.id, overlaps: overlaps.reduce((n, w) => n + (w.code === "TIME_BLOCK_OVERLAP" ? w.block_ids.length : 0), 0) };
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!form) return;
    const startsAt = new Date(`${form.date}T${form.start}`);
    const endsAt = new Date(`${form.date}T${form.end}`);
    if (!(endsAt > startsAt)) {
      setError("The end time must be after the start time.");
      return;
    }
    setSaving(true);
    setError("");
    try {
      const { id, overlaps } = await create({
        title: form.title.trim(), category: form.category,
        starts_at: startsAt.toISOString(), ends_at: endsAt.toISOString(),
      });
      const reminder = START_CHOICES.find((c) => c.id === form.reminder);
      if (reminder?.offsets.length) await reminders.setReminders("time_block", id, reminder.offsets);
      // Show the week the block landed in.
      const target = mondayOf(startsAt);
      const current = mondayOf(new Date(today ?? Date.now()));
      setOffset(Math.round((target.getTime() - current.getTime()) / (7 * 86_400_000)));
      setForm(null);
      await load();
      setNotice(overlaps
        ? `Time block added. It overlaps ${overlaps} other ${overlaps === 1 ? "block" : "blocks"}; that's allowed, just worth a look.`
        : "Time block added.");
    } catch (e) {
      setError(e instanceof Error ? e.message : "The time block could not be saved.");
    } finally {
      setSaving(false);
    }
  }

  async function remove(block: TimeBlock) {
    setSaving(true);
    setError("");
    setNotice("");
    setDeleted(null);
    try {
      await apiRequest(`/time-blocks/${block.id}`, { method: "DELETE" });
      await load();
      setDeleted(block);
    } catch (e) {
      setError(e instanceof Error ? e.message : "The time block could not be deleted.");
    } finally {
      setSaving(false);
    }
  }

  // A deleted block's id cannot be reused, so Undo creates it again as a new block.
  async function undoDelete() {
    if (!deleted) return;
    setSaving(true);
    try {
      await create({ title: deleted.title, category: deleted.category, starts_at: deleted.starts_at, ends_at: deleted.ends_at });
      await load();
      setNotice(`“${deleted.title}” restored.`);
      setDeleted(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "The time block could not be restored.");
    } finally {
      setSaving(false);
    }
  }

  const set = (key: keyof BlockForm) => (e: { target: { value: string } }) =>
    setForm((current) => (current ? { ...current, [key]: e.target.value } : current));
  const title = weekTitle(offset, monday);
  const weekCount = blocks.length;

  return (
    <div className="page-content">
      <div className="page-heading">
        <div>
          <p className="eyebrow">Protected time</p>
          <h1>Make space for the work.</h1>
          <p className="page-lede">See the commitments that give your week a little more shape.</p>
        </div>
        <button className="button button-primary" type="button" onClick={openForm} disabled={!workspace}>＋ Add time block</button>
      </div>
      {error && <div className="notice notice-error" role="alert">{error}</div>}
      {notice && <div className="notice" role="status">{notice}</div>}
      {deleted && <UndoBar message={`“${deleted.title}” deleted.`} busy={saving} onUndo={() => void undoDelete()} onDismiss={() => setDeleted(null)} />}

      {form && (
        <section ref={formRef} className="panel grant-form-panel" aria-labelledby="block-form-title">
          <div className="panel-heading">
            <div><p className="eyebrow">Time block</p><h2 id="block-form-title">New time block</h2></div>
            <button className="button button-secondary" type="button" onClick={() => setForm(null)}>Cancel</button>
          </div>
          <form className="grant-form" onSubmit={(e) => void save(e)}>
            <div className="grant-form-grid">
              <label>What is it for?<input required maxLength={240} value={form.title} onChange={set("title")} placeholder="e.g. Write the MIPT motivation letter" /></label>
              <label>Type<select value={form.category} onChange={set("category")}>{CATEGORIES.map((c) => <option key={c}>{c}</option>)}</select></label>
              <label>Remind me<select value={form.reminder} onChange={set("reminder")}>{START_CHOICES.map((c) => <option key={c.id} value={c.id}>{c.label}</option>)}</select></label>
              <label>Date<input required type="date" value={form.date} onChange={set("date")} /></label>
              <div className="block-times">
                <label>Starts<input required type="time" value={form.start} onChange={set("start")} /></label>
                <label>Ends<input required type="time" value={form.end} onChange={set("end")} /></label>
              </div>
            </div>
            <div className="grant-form-actions">
              <button className="button button-primary" type="submit" disabled={saving}>{saving ? "Saving…" : "Add time block"}</button>
              <button className="button button-secondary" type="button" onClick={() => setForm(null)} disabled={saving}>Cancel</button>
            </div>
          </form>
        </section>
      )}

      <section className="calendar-layout">
        <div className="panel calendar-card">
          <div className="calendar-toolbar">
            <button className="icon-button" type="button" aria-label="Previous week" onClick={() => setOffset((value) => value - 1)}>←</button>
            <h2 aria-live="polite">{title}</h2>
            <button className="icon-button" type="button" aria-label="Next week" onClick={() => setOffset((value) => value + 1)}>→</button>
          </div>
          <div className="week-grid">
            {days.map(({ label, date }) => {
              const isToday = date !== null && date.toDateString() === today;
              const dayBlocks = blocksOn(date);
              return (
                <div className={`day-column ${isToday ? "today" : ""}`} key={label} aria-current={isToday ? "date" : undefined}>
                  <span>{label}</span>
                  <b>{date ? date.getDate() : " "}</b>
                  <div className="day-line" />
                  <ul className="day-blocks">
                    {dayBlocks.map((block) => (
                      <li key={block.id} className="time-block" data-category={block.category.toLowerCase()}>
                        <span className="time-block-time">{timeLabel(block.starts_at)}–{timeLabel(block.ends_at)}</span>
                        <strong>{block.title}</strong>
                        <span className="time-block-category">{block.category}</span>
                        <div className="time-block-actions">
                          <ReminderPicker
                            label={`Reminder for ${block.title}`}
                            choices={START_CHOICES}
                            current={reminders.offsetsFor("time_block", block.id)}
                            onChange={async (offsets) => (await reminders.setReminders("time_block", block.id, offsets))
                              ? "That time has already passed." : ""}
                          />
                          <button type="button" className="time-block-delete" onClick={() => void remove(block)} disabled={saving} aria-label={`Delete ${block.title}`}>×</button>
                        </div>
                      </li>
                    ))}
                  </ul>
                </div>
              );
            })}
          </div>
          {weekCount === 0 && (
            <div className="calendar-empty">
              <span className="empty-icon" aria-hidden="true">□</span>
              <h3>Your week is open.</h3>
              <p>Add a block when you know what deserves uninterrupted attention.</p>
            </div>
          )}
        </div>
        <aside className="panel panel-tinted">
          <p className="eyebrow">Planning principle</p>
          <h2>Leave a little white space.</h2>
          <p>{weekCount
            ? `${weekCount} ${weekCount === 1 ? "block" : "blocks"} planned ${offset === 0 ? "this week" : "in this week"}. Keep some time unclaimed.`
            : "A calendar is more useful when it holds both commitments and breathing room. Overlap warnings will never block a save."}</p>
        </aside>
      </section>
    </div>
  );
}
