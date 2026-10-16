import type { Session } from "@/lib/types/domain";
const key = "omniassist_session";
export function saveSession(session: Session) { window.localStorage.setItem(key, JSON.stringify(session)); window.localStorage.setItem("omniassist_access_token", session.access_token); document.cookie = "omniassist_session=1; path=/; max-age=2592000; samesite=lax"; }
export function readSession(): Session | null { try { const raw = window.localStorage.getItem(key); return raw ? (JSON.parse(raw) as Session) : null; } catch { return null; } }
export function clearSession() { window.localStorage.removeItem(key); window.localStorage.removeItem("omniassist_access_token"); document.cookie = "omniassist_session=; path=/; max-age=0; samesite=lax"; }
