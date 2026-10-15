import pytest
from pydantic import ValidationError

from src.domain.common.errors import DomainError, ErrorCode
from src.domain.time_blocks.schemas import BlockStatus, TimeBlockCreate, TimeBlockUpdate
from src.domain.time_blocks.service import ALLOWED, check_transition

WS = "00000000-0000-0000-0000-000000000001"
T0, T1 = "2026-10-15T09:00:00Z", "2026-10-15T10:00:00Z"


def test_inverted_or_empty_block_rejected() -> None:
    for start, end in ((T1, T0), (T0, T0)):
        with pytest.raises(ValidationError):
            TimeBlockCreate(workspace_id=WS, title="x", starts_at=start, ends_at=end)


def test_naive_times_rejected() -> None:
    with pytest.raises(ValidationError):
        TimeBlockCreate(workspace_id=WS, title="x", starts_at="2026-10-15T09:00:00", ends_at=T1)


def test_update_with_both_times_checks_order() -> None:
    with pytest.raises(ValidationError):
        TimeBlockUpdate(starts_at=T1, ends_at=T0)
    assert TimeBlockUpdate(starts_at=T0).changes() == {
        "starts_at": TimeBlockUpdate(starts_at=T0).starts_at
    }


@pytest.mark.parametrize(
    ("a", "b"),
    [(a, b) for a, targets in ALLOWED.items() for b in targets],
)
def test_allowed_transitions(a: BlockStatus, b: BlockStatus) -> None:
    check_transition(a.value, b.value)


@pytest.mark.parametrize(
    ("a", "b"),
    [
        (BlockStatus.complete, BlockStatus.in_progress),
        (BlockStatus.complete, BlockStatus.cancelled),
        (BlockStatus.skipped, BlockStatus.complete),
        (BlockStatus.cancelled, BlockStatus.in_progress),
    ],
)
def test_forbidden_transitions(a: BlockStatus, b: BlockStatus) -> None:
    with pytest.raises(DomainError) as e:
        check_transition(a.value, b.value)
    assert e.value.code == ErrorCode.DOMAIN_RULE_VIOLATION


def test_same_status_is_a_noop() -> None:
    check_transition("complete", "complete")
