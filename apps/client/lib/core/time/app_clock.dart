abstract interface class AppClock {
  DateTime now();
}

class SystemClock implements AppClock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now().toUtc();
}

class FixedClock implements AppClock {
  FixedClock(this._at);
  DateTime _at;
  @override
  DateTime now() => _at;
  void advance(Duration d) => _at = _at.add(d);
}

/// ISO 8601 UTC with trailing Z, the wire format for every timestamp.
String toUtcIso(DateTime t) => t.toUtc().toIso8601String();
