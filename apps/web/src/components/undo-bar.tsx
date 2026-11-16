"use client";

import { useEffect, useRef } from "react";

/**
 * A short-lived message after a delete, with a way to take it back. It closes by itself after
 * `timeoutMs`, or when the person dismisses it. Undo restores the deleted record as a new one.
 */
export function UndoBar({ message, busy, onUndo, onDismiss, timeoutMs = 10000 }: {
  message: string;
  busy: boolean;
  onUndo: () => void;
  onDismiss: () => void;
  timeoutMs?: number;
}) {
  // Hold the latest callback so a parent re-render does not restart the countdown.
  const dismiss = useRef(onDismiss);
  useEffect(() => { dismiss.current = onDismiss; }, [onDismiss]);
  useEffect(() => {
    if (busy) return;
    const timer = window.setTimeout(() => dismiss.current(), timeoutMs);
    return () => window.clearTimeout(timer);
  }, [message, busy, timeoutMs]);

  return (
    <div className="undo-bar" role="status">
      <span>{message}</span>
      <button className="undo-action" type="button" onClick={onUndo} disabled={busy}>Undo</button>
      <button className="undo-dismiss" type="button" onClick={onDismiss} aria-label="Dismiss">×</button>
    </div>
  );
}
