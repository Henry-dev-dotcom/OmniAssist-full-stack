import json
import uuid
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.auth.provider import Identity
from src.domain.common.ids import new_uuid7

COLUMNS = "id, email, display_name, timezone, preferences"


async def upsert_by_subject(s: AsyncSession, identity: Identity) -> dict[str, Any]:
    """Map a provider identity to a local user, creating it on first sight."""
    name = identity.name or identity.email.split("@")[0]
    row = await s.execute(
        text(
            f"""INSERT INTO users (id, email, display_name, auth_subject)
            VALUES (:id, :email, :name, :sub)
            ON CONFLICT (auth_subject) DO UPDATE SET email = EXCLUDED.email
            RETURNING {COLUMNS}"""
        ),
        {"id": new_uuid7(), "email": identity.email, "name": name, "sub": identity.subject},
    )
    await s.commit()
    return dict(row.mappings().one())


async def update_profile(
    s: AsyncSession, user_id: uuid.UUID, fields: dict[str, Any]
) -> dict[str, Any]:
    sets = []
    params: dict[str, Any] = {"id": user_id}
    for key in ("display_name", "timezone"):
        if key in fields:
            sets.append(f"{key} = :{key}")
            params[key] = fields[key]
    if "preferences" in fields:
        sets.append("preferences = CAST(:preferences AS jsonb)")
        params["preferences"] = json.dumps(fields["preferences"])
    sets.append("updated_at = now()")
    row = await s.execute(
        text(f"UPDATE users SET {', '.join(sets)} WHERE id = :id RETURNING {COLUMNS}"), params
    )
    await s.commit()
    return dict(row.mappings().one())
