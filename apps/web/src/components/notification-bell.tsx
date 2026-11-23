"use client";

import { useCallback, useEffect, useId, useRef, useState } from "react";
import { apiRequest } from "@/lib/api/client";
import type { Workspace } from "@/lib/types/domain";
import { isSubscribed, pushSupported, turnOffPush, turnOnPush } from "@/lib/push";

type Notice = {
  id: string;
  title: string;
  remind_at: string;
  sent_at: string | null;
  read_at: string | null;
  delivery_status: string;
};

const POLL_MS = 60_000;
const when = (iso: string) =>
  new Date(iso).toLocaleString(undefined, { day: "numeric", month: "short", hour: "numeric", minute: "2-digit" });

function BellIcon() {
  return (
    <svg className="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
      <path d="M6 9.5a6 6 0 0 1 12 0c0 4.5 1.5 6 2 6.5H4c.5-.5 2-2 2-6.5" /><path d="M10 19.5a2 2 0 0 0 4 0" />
    </svg>
  );
}

/** The bell in the top bar: delivered reminders, unread count, and push on this device. */
export function NotificationBell() {
  const [workspace, setWorkspace] = useState<Workspace | null>(null);
  const [items, setItems] = useState<Notice[]>([]);
  const [open, setOpen] = useState(false);
  const [push, setPush] = useState<"unknown" | "on" | "off" | "unsupported">("unknown");
  const [pushMessage, setPushMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const panelId = useId();
  const button = useRef<HTMLButtonElement>(null);
  const panel = useRef<HTMLDivElement>(null);

  const load = useCallback(async () => {
    try {
      const ws = workspace ?? (await apiRequest<Workspace[]>("/workspaces")).data[0] ?? null;
      if (!ws) return;
      if (!workspace) setWorkspace(ws);
      const rows = (await apiRequest<Notice[]>(`/notifications?workspace_id=${ws.id}`)).data;
      setItems(rows.filter((n) => n.delivery_status !== "dismissed").slice(0, 30));
    } catch {
      // The bell stays quiet if the API is unreachable; pages report their own errors.
    }
  }, [workspace]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
    const timer = window.setInterval(() => { if (document.visibilityState === "visible") void load(); }, POLL_MS);
    return () => window.clearInterval(timer);
  }, [load]);

  useEffect(() => {
    // A reminder tapped on the device opens the app with ?notifications=open.
    if (new URLSearchParams(window.location.search).get("notifications") === "open") {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setOpen(true);
    }
    if (!pushSupported()) { setPush("unsupported"); return; }
    void isSubscribed().then((on) => setPush(on ? "on" : "off"));
  }, []);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") { setOpen(false); button.current?.focus(); } };
    const onPointer = (e: PointerEvent) => {
      const t = e.target as Node;
      if (!panel.current?.contains(t) && !button.current?.contains(t)) setOpen(false);
    };
    document.addEventListener("keydown", onKey);
    document.addEventListener("pointerdown", onPointer);
    return () => { document.removeEventListener("keydown", onKey); document.removeEventListener("pointerdown", onPointer); };
  }, [open]);

  const unread = items.filter((n) => !n.read_at && (n.delivery_status === "sent" || n.delivery_status === "failed")).length;

  async function act(n: Notice, action: "read" | "dismiss") {
    try {
      await apiRequest(`/notifications/${n.id}/${action}`, { method: "POST" });
      await load();
    } catch {
      // Leave the row as it is; the next refresh shows the server's state.
    }
  }

  async function readAll() {
    setBusy(true);
    await Promise.all(items.filter((n) => !n.read_at).map((n) => apiRequest(`/notifications/${n.id}/read`, { method: "POST" }).catch(() => undefined)));
    await load();
    setBusy(false);
  }

  async function togglePush() {
    setBusy(true);
    setPushMessage("");
    try {
      if (push === "on") {
        await turnOffPush();
        setPush("off");
        setPushMessage("Notifications are off on this device. Reminders still appear here.");
      } else {
        const result = await turnOnPush();
        if (result === "on") { setPush("on"); setPushMessage("Reminders will now also arrive as notifications on this device."); }
        else if (result === "denied") setPushMessage("Notifications are blocked for this site. Allow them in your browser's site settings, then try again.");
        else if (result === "not-configured") setPushMessage("Device notifications aren't set up on the server yet. Reminders still appear here.");
        else setPushMessage("This browser can't receive notifications. On iPhone, add OmniAssist to your Home Screen first.");
      }
    } catch (e) {
      setPushMessage(e instanceof Error ? e.message : "That didn't work. Try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="bell">
      <button
        ref={button}
        type="button"
        className="bell-button"
        aria-expanded={open}
        aria-controls={panelId}
        aria-label={unread ? `Reminders, ${unread} unread` : "Reminders"}
        onClick={() => setOpen((v) => !v)}
      >
        <BellIcon />
        {unread > 0 && <span className="bell-count" aria-hidden="true">{unread > 9 ? "9+" : unread}</span>}
      </button>
      {open && (
        <div className="bell-panel" id={panelId} ref={panel} role="region" aria-label="Reminders">
          <div className="bell-panel-head">
            <h2>Reminders</h2>
            {unread > 0 && <button type="button" className="text-button" onClick={() => void readAll()} disabled={busy}>Mark all read</button>}
          </div>
          {items.length ? (
            <ul className="bell-list">
              {items.map((n) => (
                <li key={n.id} className={n.read_at ? "" : "unread"}>
                  <button type="button" className="bell-item" onClick={() => void act(n, "read")}>
                    <strong>{n.title}</strong>
                    <span>{when(n.sent_at ?? n.remind_at)}{n.delivery_status === "snoozed" ? " · snoozed" : ""}</span>
                  </button>
                  <button type="button" className="bell-dismiss" onClick={() => void act(n, "dismiss")} aria-label={`Dismiss ${n.title}`}>×</button>
                </li>
              ))}
            </ul>
          ) : (
            <p className="bell-empty">No reminders yet. Set one with “Remind me” on a grant, scholarship, milestone or time block.</p>
          )}
          <div className="bell-push">
            {push === "unsupported" ? (
              <p>This browser can&rsquo;t show notifications, so reminders appear here only.</p>
            ) : (
              <button type="button" className="button button-secondary" onClick={() => void togglePush()} disabled={busy || push === "unknown"}>
                {push === "on" ? "Turn off notifications on this device" : "Get reminders on this device"}
              </button>
            )}
            {pushMessage && <p role="status">{pushMessage}</p>}
          </div>
        </div>
      )}
    </div>
  );
}
