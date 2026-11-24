"use client";
import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { apiRequest } from "@/lib/api/client";
import type { Workspace } from "@/lib/types/domain";

/**
 * Names the workspace. A new account creates its workspace here; someone who already has one
 * renames it instead, so visiting this page again never adds an empty second workspace.
 */
export default function OnboardingPage() {
  const router = useRouter();
  const [existing, setExisting] = useState<Workspace | null>(null);
  const [checked, setChecked] = useState(false);
  const [name, setName] = useState("My workspace");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    apiRequest<Workspace[]>("/workspaces")
      .then(({ data }) => {
        const current = data[0] ?? null;
        setExisting(current);
        if (current) setName(current.name);
      })
      .catch(() => undefined)
      .finally(() => setChecked(true));
  }, []);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;
    setBusy(true);
    setError("");
    try {
      if (existing) await apiRequest(`/workspaces/${existing.id}`, { method: "PATCH", body: { name: name.trim() } });
      else await apiRequest("/workspaces", { method: "POST", body: { name: name.trim() } });
      router.push("/app/today");
    } catch {
      setError(existing ? "We could not rename your workspace. Please try again." : "We could not create that workspace yet. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="auth-page">
      <div className="auth-card onboarding-card">
        <span className="brand-symbol" aria-hidden="true">∞</span>
        <p className="eyebrow">{existing ? "Workspace settings" : "First, make it yours"}</p>
        <h1>{existing ? "Rename your workspace." : "Give your workspace a name."}</h1>
        <p className="auth-intro">This is where your projects, tasks, applications and notes will live.</p>
        <form onSubmit={(e) => void submit(e)}>
          <label>Workspace name<input autoFocus required maxLength={120} value={name} onChange={(e) => setName(e.target.value)} /></label>
          {error && <p className="form-error" role="alert">{error}</p>}
          <button className="button button-primary button-wide" disabled={busy || !checked}>
            {busy ? "Saving…" : existing ? "Save name" : "Continue to workspace"}
          </button>
          {existing && <button className="button button-secondary button-wide" type="button" onClick={() => router.push("/app/today")}>Back to workspace</button>}
        </form>
      </div>
    </main>
  );
}
