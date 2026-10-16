# 0006. Reminder notifications through Web Push

Status: accepted (2026-10-16). Settles Spec 12.4 "notification channels" for the web app:
push and the in-app center; no email.

## Decision
- The installed web app receives reminders through the standard Web Push protocol
  (VAPID, RFC 8030/8291/8292) via `pywebpush`. Works in desktop browsers and on Android;
  on iPhone (iOS 16.4+) after the app is added to the Home Screen.
- A device opts in from Settings ("Reminder notifications on this device"). The browser asks
  for permission only after that tap. Signing out removes the device's subscription.
- The device keeps reminders locally (in-app center, offline). It mirrors each task's
  reminders to the server (`PUT /tasks/{id}/reminders`); if that fails, the task waits in a
  persisted list and is sent after the next successful sync.
- The reminder worker (`src.workers.reminder_worker`, a `worker` service in production) sends
  due reminders. Quiet hours and urgency are applied server-side as before; urgency maps to the
  push `Urgency` header. Subscriptions the browser reports gone (404/410) are deleted.
- Payloads are encrypted to each device, so push services cannot read them. They carry the
  task title and a link to the notification center; logs never include them.
- Configure with `OMNI_VAPID_PRIVATE_KEY`, `OMNI_VAPID_PUBLIC_KEY`, `OMNI_VAPID_SUBJECT`
  (generate with `uv run python -m src.infrastructure.notifications.webpush`). Without keys
  the app falls back to the in-app center only.

## Consequences
- The server stores one row per subscribed device (`push_subscriptions`), deleted with the account.
- Native builds still need a platform plugin for OS notifications.
- A phone that both shows an in-app reminder and receives the push sees it in two places, never
  as two OS notifications (the web app shows OS notifications only through push).
