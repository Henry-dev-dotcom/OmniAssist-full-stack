import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.common.errors import DomainError, ErrorCode
from src.domain.workspaces import repository


async def require_member(s: AsyncSession, workspace_id: uuid.UUID, user_id: uuid.UUID) -> None:
    """Every workspace-scoped request passes through here (Spec 9.2)."""
    if not await repository.is_member(s, workspace_id, user_id):
        raise DomainError(ErrorCode.FORBIDDEN, "You do not have access to this workspace.")
