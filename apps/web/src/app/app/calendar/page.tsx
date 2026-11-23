"use client";
import { useEffect, useMemo, useState, useSyncExternalStore } from "react";
import { apiRequest } from "@/lib/api/client";
import type { TimeBlock, Workspace } from "@/lib/types/domain";

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri"];

// Today's date comes from the browser clock; the server renders without dates, so the two never disagree.
const noSubscribe = () => () => {};
const todayKey = () => new Date().toDateString();
const serverToday = () => null;

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
  const [blocks, setBlocks] = useState<TimeBlock[]>([]);
  const [error, setError] = useState("");
  const [offset, setOffset] = useState(0);
  const today = useSyncExternalStore(noSubscribe, todayKey, serverToday);

  useEffect(() => {
    async function load() {
      try {
        const ws = (await apiRequest<Workspace[]>("/workspaces")).data[0];
        if (ws) setBlocks((await apiRequest<TimeBlock[]>(`/time-blocks?workspace_id=${ws.id}`)).data);
      } catch {
        setError("Calendar data is not available yet.");
      }
    }
    void load();
  }, []);

  const monday = useMemo(() => {
    if (!today) return null;
    const start = mondayOf(new Date(today));
    start.setDate(start.getDate() + offset * 7);
    return start;
  }, [today, offset]);

  const days = DAYS.map((label, index) => {
    if (!monday) return { label, date: null as Date | null };
    const date = new Date(monday);
    date.setDate(monday.getDate() + index);
    return { label, date };
  });
  const title = weekTitle(offset, monday);

  return (
    <div className="page-content">
      <div className="page-heading">
        <div>
          <p className="eyebrow">Protected time</p>
          <h1>Make space for the work.</h1>
          <p className="page-lede">See the commitments that give your week a little more shape.</p>
        </div>
        <button className="button button-primary">＋ Add time block</button>
      </div>
      {error && <div className="notice notice-error">{error}</div>}
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
              return (
                <div className={`day-column ${isToday ? "today" : ""}`} key={label} aria-current={isToday ? "date" : undefined}>
                  <span>{label}</span>
                  <b>{date ? date.getDate() : " "}</b>
                  <div className="day-line" />
                </div>
              );
            })}
          </div>
          <div className="calendar-empty">
            <span className="empty-icon" aria-hidden="true">□</span>
            <h3>{blocks.length ? `${blocks.length} blocks planned` : "Your week is open."}</h3>
            <p>{blocks.length ? "Keep your protected time visible as plans change." : "Add a block when you know what deserves uninterrupted attention."}</p>
          </div>
        </div>
        <aside className="panel panel-tinted">
          <p className="eyebrow">Planning principle</p>
          <h2>Leave a little white space.</h2>
          <p>A calendar is more useful when it holds both commitments and breathing room. Overlap warnings will never block a save.</p>
        </aside>
      </section>
    </div>
  );
}
