"""Operator password reset for built-in sign-in (decision 0002 has no email service).

    uv run python -m src.auth.reset_password user@example.com

Sets a random temporary password, ends every session of that account, and prints the
password once. Give it to the user through a trusted channel; they change it in Settings.
"""

import asyncio
import secrets
import sys

from sqlalchemy import text

from src.auth.local_provider import LocalProvider
from src.config import settings
from src.infrastructure.database.session import SessionFactory


async def reset(email: str) -> str | None:
    async with SessionFactory() as s:
        subject = (
            await s.execute(
                text("SELECT subject FROM local_credentials WHERE lower(email) = lower(:e)"),
                {"e": email},
            )
        ).scalar_one_or_none()
    if subject is None:
        return None
    temporary = secrets.token_urlsafe(12)
    provider = LocalProvider(secret=settings.auth_local_secret, sessions=SessionFactory)
    await provider.set_password(subject, temporary)
    return temporary


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    temporary = asyncio.run(reset(sys.argv[1]))
    if temporary is None:
        print("No account with that email uses built-in sign-in.")
        return 1
    print(f"Temporary password (shown once): {temporary}")
    print("All sessions of this account have ended.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
