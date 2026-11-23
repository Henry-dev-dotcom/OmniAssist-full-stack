"use client";

import { useEffect, useRef } from "react";

/**
 * Brings an inline form into view when it opens, puts the cursor in its first field, and hands
 * focus back to whatever opened it (an Edit button, say) when it closes. Without this, opening a
 * form from far down a long list happened thousands of pixels away, out of sight.
 *
 * `openKey` is falsy while closed; give each record its own key so switching straight from one
 * Edit to another runs again.
 */
export function useFormFocus<T extends HTMLElement>(openKey: string | boolean | null) {
  const ref = useRef<T>(null);
  useEffect(() => {
    const form = ref.current;
    if (!openKey || !form) return;
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    form.scrollIntoView({ block: "start", behavior: reduce ? "auto" : "smooth" });
    form.querySelector<HTMLElement>("input, select, textarea")?.focus({ preventScroll: true });
    return () => {
      // Only when focus would otherwise be lost: it was inside the form, or fell back to the page.
      // Pressing a different Edit button keeps focus on that button.
      const active = document.activeElement;
      const lost = !active || active === document.body || form.contains(active);
      if (lost && opener?.isConnected) opener.focus();
    };
  }, [openKey]);
  return ref;
}
