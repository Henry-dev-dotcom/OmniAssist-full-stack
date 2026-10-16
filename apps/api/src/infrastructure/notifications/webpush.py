"""Web Push delivery (decision 0006). Payloads are encrypted to each device (RFC 8291), so
the browser's push service never sees reminder text.

    uv run python -m src.infrastructure.notifications.webpush   # prints a new key pair
"""

import asyncio
import json
import logging
import uuid

from cryptography.hazmat.primitives import serialization
from py_vapid import Vapid01, b64urlencode
from pywebpush import WebPushException, webpush
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from src.infrastructure.notifications.gateway import Message

log = logging.getLogger("omni.push")

# Push services keep high-urgency messages for delivery first (RFC 8030 Urgency header).
URGENCY = {"low": "low", "normal": "normal", "high": "high", "critical": "high"}


def generate_keys() -> tuple[str, str]:
    """(private, public) as base64url: private for the server, public for browsers."""
    v = Vapid01()
    v.generate_keys()
    raw = v.private_key.private_numbers().private_value.to_bytes(32, "big")
    public = v.public_key.public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
    )
    return b64urlencode(raw), b64urlencode(public)


class WebPushGateway:
    """Sends a push to every device the recipient enabled. The in-app notification center
    has the reminder either way, so a push failure never fails the reminder."""

    def __init__(
        self, sessions: async_sessionmaker[AsyncSession], private_key: str, subject: str
    ) -> None:
        self._sessions = sessions
        self._key = private_key
        self._subject = subject

    async def send(self, message: Message) -> None:
        if not message.user_id:
            return
        async with self._sessions() as s:
            rows = await s.execute(
                text("SELECT endpoint, p256dh, auth FROM push_subscriptions WHERE user_id = :u"),
                {"u": uuid.UUID(message.user_id)},
            )
            subs = [dict(r) for r in rows.mappings()]
        payload = json.dumps(
            {
                "title": message.title or "Reminder",
                "tag": message.notification_id,
                "url": "/#/app/notifications",
            }
        )
        gone = []
        for sub in subs:
            try:
                await asyncio.to_thread(
                    webpush,
                    subscription_info={
                        "endpoint": sub["endpoint"],
                        "keys": {"p256dh": sub["p256dh"], "auth": sub["auth"]},
                    },
                    data=payload,
                    vapid_private_key=self._key,
                    vapid_claims={"sub": self._subject},
                    ttl=24 * 3600,
                    timeout=10,
                    headers={"Urgency": URGENCY.get(message.urgency, "normal")},
                )
            except WebPushException as e:
                status = e.response.status_code if e.response is not None else None
                if status in (404, 410):  # the browser dropped this subscription
                    gone.append(sub["endpoint"])
                else:
                    log.warning("push failed with status %s", status)  # never the content
            except Exception:  # noqa: BLE001 - network trouble must not stop other reminders
                log.warning("push failed: unreachable")
        if gone:
            async with self._sessions() as s:
                await s.execute(
                    text("DELETE FROM push_subscriptions WHERE endpoint = ANY(:e)"), {"e": gone}
                )
                await s.commit()


if __name__ == "__main__":  # pragma: no cover
    private, public = generate_keys()
    print(f"OMNI_VAPID_PRIVATE_KEY={private}")
    print(f"OMNI_VAPID_PUBLIC_KEY={public}")
