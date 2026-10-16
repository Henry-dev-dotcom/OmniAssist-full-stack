# Running OmniAssist for yourself, on your PC and phone

No server and no domain needed. Your PC runs OmniAssist; your phone and your PC each keep their
own copy of your data, so both work offline, and they sync whenever your phone can reach the PC.

## 1. Start it on the PC

```
powershell -ExecutionPolicy Bypass -File scripts\start-omniassist.ps1
```

Open **http://localhost:8000**, choose *Create an account*, and you're in. Leave the window
open while you use it; closing it stops everything. After updating the code, add `-Build`
to rebuild the app first.

When your account exists, stop other people creating one: put `OMNI_ALLOW_REGISTRATION=false`
in `apps/api/.env` and restart.

**Start it automatically at login** (optional): press Win+R, type `shell:startup`, and put a
shortcut there with the target
`powershell -WindowStyle Minimized -ExecutionPolicy Bypass -File "C:\path\to\omniassist\scripts\start-omniassist.ps1"`.

## 2. Use it on your phone

A phone only lets a web app **install, work offline and show notifications** over a secure
(`https://`) address, and your PC at home has none. The easiest free fix is **Tailscale**, a
private network between your own devices that also gives them a secure address:

1. Install Tailscale on the PC and on the phone (tailscale.com/download) and sign in with the
   same account on both.
2. In the Tailscale admin page (login.tailscale.com), under *DNS*, turn on **MagicDNS** and
   **HTTPS Certificates**.
3. On the PC, in a terminal: `tailscale serve --bg 8000`. It prints your address, like
   `https://your-pc.tail1234.ts.net`. (Run `tailscale serve status` to see it again.)
4. On the phone, open that address in Chrome (Android) or Safari (iPhone), sign in, then
   **Install app** / **Add to Home Screen**.

Only your own devices can reach that address, even away from home. If the PC is off or asleep,
the phone still works and catches up the next time the PC is on.

> This guide was written without Tailscale installed on the development machine, so step 3 was
> not run here. If the command differs on your version, `tailscale serve --help` shows the form.

**Without Tailscale:** start with `-BindAll`, allow the Windows firewall prompt, and open
`http://<your PC's IP>:8000` on the phone while on the same Wi-Fi. It works like a normal
website, but the phone cannot install it, use it offline, or show notifications.

## 3. Notifications on the phone (optional)

1. Generate keys once: `cd apps\api` then `uv run python -m src.infrastructure.notifications.webpush`.
2. Add the printed three lines to `apps/api/.env` and restart the script.
3. On the phone: *Settings → Reminder notifications on this device*.

Reminders reach a closed phone app only while the PC is on. With the app open they always show.

## 4. Keep your data safe

Everything lives in the PostgreSQL database on the PC. Back it up now and then:

```
python infra\scripts\backup_restore.py backup --url postgresql://omni:omni@localhost:5435/omniassist --out omni.dump
```

Copy `omni.dump` somewhere else (a USB drive or cloud folder). `docs/operations.md` explains
restoring. In the app, *Settings → Export my data* gives you a readable copy too.

## Troubleshooting

- **Phone says it can't reach the server:** is the PC on and the script running? Is Tailscale
  connected on both? The app keeps working offline either way.
- **Forgot your password:** `cd apps\api` then
  `uv run python -m src.auth.reset_password you@example.com` prints a temporary one.
- **Port 8000 busy:** run the script with `-Port 8001` (and `tailscale serve --bg 8001`).
