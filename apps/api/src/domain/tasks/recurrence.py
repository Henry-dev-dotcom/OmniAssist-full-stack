"""Recurrence rules: a small subset of RFC 5545 RRULE (decision 0005).

    FREQ=DAILY|WEEKLY|MONTHLY|YEARLY      required
    INTERVAL=1..365                        optional, default 1
    BYDAY=MO,TU,WE,TH,FR,SA,SU             optional, WEEKLY only

The client computes the next occurrence; the server only checks the rule is valid.
"""

FREQS = {"DAILY", "WEEKLY", "MONTHLY", "YEARLY"}
DAYS = ("MO", "TU", "WE", "TH", "FR", "SA", "SU")


def validate_rule(rule: str) -> str:
    """Returns the rule, or raises ValueError with a message fit for the form field."""
    parts: dict[str, str] = {}
    for item in rule.strip().split(";"):
        key, sep, value = item.partition("=")
        if not sep or not key or not value:
            raise ValueError("use KEY=VALUE pairs separated by ';', e.g. FREQ=WEEKLY;BYDAY=MO")
        if key in parts:
            raise ValueError(f"{key} appears twice")
        parts[key] = value
    unknown = parts.keys() - {"FREQ", "INTERVAL", "BYDAY"}
    if unknown:
        raise ValueError(f"unsupported part: {', '.join(sorted(unknown))}")
    if parts.get("FREQ") not in FREQS:
        raise ValueError("FREQ must be DAILY, WEEKLY, MONTHLY or YEARLY")
    if "INTERVAL" in parts:
        n = parts["INTERVAL"]
        if not n.isdigit() or not 1 <= int(n) <= 365:
            raise ValueError("INTERVAL must be a whole number from 1 to 365")
    if "BYDAY" in parts:
        if parts["FREQ"] != "WEEKLY":
            raise ValueError("BYDAY works only with FREQ=WEEKLY")
        days = parts["BYDAY"].split(",")
        if not days or any(d not in DAYS for d in days) or len(set(days)) != len(days):
            raise ValueError("BYDAY lists days like MO,WE,FR")
    return rule.strip()
