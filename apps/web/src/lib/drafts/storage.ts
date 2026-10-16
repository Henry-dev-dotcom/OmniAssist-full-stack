const PREFIX = "omniassist-draft:";
export const MAX_DRAFT_BYTES = 256 * 1024;
const MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000;
type StoredDraft = { savedAt: number; value: unknown };

export function saveDraft(key: string, value: unknown): boolean {
  try {
    const serialized = JSON.stringify({ savedAt: Date.now(), value } satisfies StoredDraft);
    if (new TextEncoder().encode(serialized).byteLength > MAX_DRAFT_BYTES) {
      window.localStorage.removeItem(`${PREFIX}${key}`);
      return false;
    }
    window.localStorage.setItem(`${PREFIX}${key}`, serialized);
    return true;
  } catch {
    return false;
  }
}

export function loadDraft<T>(key: string): T | null {
  try {
    const storageKey = `${PREFIX}${key}`;
    const raw = window.localStorage.getItem(storageKey);
    if (!raw) return null;
    const draft = JSON.parse(raw) as StoredDraft;
    if (!Number.isSafeInteger(draft.savedAt) || Date.now() - draft.savedAt > MAX_AGE_MS) {
      window.localStorage.removeItem(storageKey);
      return null;
    }
    return draft.value as T;
  } catch {
    return null;
  }
}

export function removeDraft(key: string): void {
  try {
    window.localStorage.removeItem(`${PREFIX}${key}`);
  } catch {
    // Storage may be unavailable in private or quota-restricted browser contexts.
  }
}
