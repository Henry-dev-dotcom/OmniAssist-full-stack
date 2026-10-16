# Running OmniAssist for yourself, on your PC and phone

OmniAssist is delivered as an **installable web app (PWA)**. This is the supported cross-platform
path: one build works on Windows, macOS, Linux, Android and iPhone. On a PC it opens like a
normal desktop app and can be installed from the browser; on a phone it can be added to the home
screen. Native Android/iOS/Windows packages remain optional release builds and require their
platform SDKs and signing credentials.

No server and no domain needed. Your PC runs OmniAssist; your phone and your PC each keep their
own copy of your data, so both work offline, and they sync whenever your phone can reach the PC.

## 1. Start it on the PC

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File scripts\start-omniassist.ps1 -Build
```

### macOS or Linux

```bash
cp infra/env/.env.example apps/api/.env   # first run only; adjust the database URL if needed
chmod +x scripts/start-omniassist.sh
./scripts/start-omniassist.sh --build
```

After the first build, omit `-Build` / `--build` for faster starts. Open
**http://localhost:8000**, choose *Create an account*, and you're in. Leave the launcher window
open while you use it; closing it stops the API.

When your account exists, stop other people creating one: put
`OMNI_ALLOW_REGISTRATION=false` in `apps/api/.env` and restart.

### Install it like normal software on the PC

Open the address in Chrome or Edge and use the install icon in the address bar (or menu →
**Install OmniAssist**). On macOS/Linux, Chrome/Edge adds it to the applications menu; on Windows
it appears in the Start menu. The installed app uses the same offline storage as that browser
profile.

### Start automatically at login (optional)

On Windows, place a shortcut in `shell:startup` with target:

```text
powershell -WindowStyle Minimized -ExecutionPolicy Bypass -File "C:\path\to\omniassist\scripts\start-omniassist.ps1"
```

On macOS/Linux, add `/absolute/path/to/omniassist/scripts/start-omniassist.sh` to the user's
login/autostart settings.

## 2. Use it on your phone

A phone only lets a web app **install, work offline and show notifications** over a secure
(`https://`) address, and your PC at home has none. The easiest free fix is **Tailscale**, a
private network between your own devices that also gives them a secure address:

1. Install Tailscale on the PC and on the phone (https://tailscale.com/download) and sign in with the same account on both.
2. In the Tailscale admin page (https://login.tailscale.com), under **DNS**, turn on **MagicDNS** and **HTTPS Certificates**.
3. On the PC, in a terminal, run `tailscale serve --bg 8000`. It prints an address such as `https://your-pc.tail1234.ts.net`. Run `tailscale serve status` to see it again.
4. On the phone, open that address in Chrome (Android) or Safari (iPhone), sign in, then choose **Install app** / **Add to Home Screen**.

Only your own devices can reach that address, even away from home. If the PC is off or asleep,
the phone still works offline and catches up the next time the PC is on.

> Tailscale is not installed on the development machine, so the command was not run here. If the
> command differs on your version, `tailscale serve --help` shows the form.

**Without Tailscale:** start with `--bind-all` on macOS/Linux or `-BindAll` on Windows, allow the
firewall prompt, and open `http://<your PC's IP>:8000` on the phone while on the same Wi-Fi. It
works as a normal website, but the phone cannot install it, use it offline, or show notifications.

## 3. Notifications on the phone (optional)

1. Generate keys once: from `apps/api`, run `uv run python -m src.infrastructure.notifications.webpush`.
2. Add the printed three lines to `apps/api/.env` and restart the launcher.
3. On the phone, open **Settings → Reminder notifications on this device**.

Reminders reach a closed phone app only while the PC is on. With the app open they always show.

## 4. Keep your data safe

Everything lives in the PostgreSQL database on the PC. Back it up now and then:

```bash
python infra/scripts/backup_restore.py backup --url postgresql://omni:omni@localhost:5435/omniassist --out omni.dump
```

Copy `omni.dump` somewhere else (a USB drive or cloud folder). `docs/operations.md` explains
restoring. In the app, **Settings → Export my data** gives you a readable copy too.

## Troubleshooting

- **Phone says it can't reach the server:** is the PC on and the launcher running? Is Tailscale connected on both? The app keeps working offline either way.
- **Forgot your password:** from `apps/api`, run `uv run python -m src.auth.reset_password you@example.com` to print a temporary one.
- **Port 8000 busy:** Windows: use `-Port 8001` and `tailscale serve --bg 8001`; macOS/Linux: use `--port 8001` and `tailscale serve --bg 8001`.
