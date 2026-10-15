from src.domain.common.errors import DomainError, ErrorCode
from src.domain.time_blocks.schemas import BlockStatus as S

# Finished or dropped blocks can only be reopened to "planned".
ALLOWED: dict[S, set[S]] = {
    S.planned: {S.in_progress, S.complete, S.skipped, S.cancelled},
    S.in_progress: {S.planned, S.complete, S.skipped, S.cancelled},
    S.complete: {S.planned},
    S.skipped: {S.planned},
    S.cancelled: {S.planned},
}

# Blocks in these states do not occupy time, so they never trigger an overlap warning.
FREE_STATES = (S.skipped.value, S.cancelled.value)


def check_transition(current: str, new: str) -> None:
    a, b = S(current), S(new)
    if a != b and b not in ALLOWED[a]:
        raise DomainError(
            ErrorCode.DOMAIN_RULE_VIOLATION, f"A {a.value} block cannot become {b.value}."
        )
