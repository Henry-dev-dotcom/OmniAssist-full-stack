"use client";

import { apiRequest } from "@/lib/api/client";

/** Whether this browser can receive push reminders at all. */
export function pushSupported() {
  return typeof window !== "undefined"
    && "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;
}

function keyBytes(base64url: string) {
  const padded = (base64url + "=".repeat((4 - (base64url.length % 4)) % 4)).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(padded);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes;
}

async function registration() {
  return (await navigator.serviceWorker.getRegistration("/")) ?? navigator.serviceWorker.register("/sw.js", { scope: "/" });
}

/** True when this device already sends its reminders here. */
export async function isSubscribed() {
  if (!pushSupported()) return false;
  const reg = await navigator.serviceWorker.getRegistration("/");
  return Boolean(await reg?.pushManager.getSubscription());
}

export type PushResult = "on" | "denied" | "unsupported" | "not-configured";

/** Asks permission and subscribes this device. Reminders show in the app whatever the answer. */
export async function turnOnPush(): Promise<PushResult> {
  if (!pushSupported()) return "unsupported";
  let publicKey: string;
  try {
    publicKey = (await apiRequest<{ public_key: string }>("/push/public-key")).data.public_key;
  } catch {
    return "not-configured";
  }
  if ((await Notification.requestPermission()) !== "granted") return "denied";
  const reg = await registration();
  await navigator.serviceWorker.ready;
  const subscription = (await reg.pushManager.getSubscription())
    ?? (await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(publicKey) }));
  await apiRequest("/push/subscriptions", { method: "POST", body: subscription.toJSON() as Record<string, unknown> });
  return "on";
}

export async function turnOffPush() {
  if (!pushSupported()) return;
  const reg = await navigator.serviceWorker.getRegistration("/");
  const subscription = await reg?.pushManager.getSubscription();
  if (!subscription) return;
  await apiRequest("/push/subscriptions/remove", { method: "POST", body: { endpoint: subscription.endpoint } });
  await subscription.unsubscribe();
}
