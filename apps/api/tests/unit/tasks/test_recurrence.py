import pytest

from src.domain.tasks.recurrence import validate_rule


@pytest.mark.parametrize(
    "rule",
    ["FREQ=DAILY", "FREQ=WEEKLY;BYDAY=MO,WE,FR", "FREQ=MONTHLY;INTERVAL=2", " FREQ=YEARLY "],
)
def test_valid_rules(rule: str) -> None:
    assert validate_rule(rule) == rule.strip()


@pytest.mark.parametrize(
    "rule,why",
    [
        ("FREQ=HOURLY", "FREQ must be"),
        ("FREQ=DAILY;INTERVAL=0", "INTERVAL"),
        ("FREQ=DAILY;INTERVAL=x", "INTERVAL"),
        ("FREQ=DAILY;BYDAY=MO", "only with FREQ=WEEKLY"),
        ("FREQ=WEEKLY;BYDAY=MO,XX", "BYDAY lists"),
        ("FREQ=WEEKLY;BYDAY=MO,MO", "BYDAY lists"),
        ("FREQ=DAILY;COUNT=3", "unsupported part: COUNT"),
        ("FREQ=DAILY;FREQ=WEEKLY", "appears twice"),
        ("every day", "KEY=VALUE"),
    ],
)
def test_invalid_rules_explain_the_field(rule: str, why: str) -> None:
    with pytest.raises(ValueError, match=why):
        validate_rule(rule)
