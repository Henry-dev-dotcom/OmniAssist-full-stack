import 'dart:math';

/// Retry waits from sync_protocol.md: 5s, 15s, 1m, 5m, 15m, then 30m.
/// [attempt] counts failures so far (1 = first retry). Jitter is +/-20%.
Duration retryDelay(int attempt, {Random? random}) {
  const steps = [5, 15, 60, 300, 900];
  final base = attempt <= 0
      ? steps.first
      : attempt <= steps.length
      ? steps[attempt - 1]
      : 1800;
  final jitter = 0.8 + 0.4 * (random ?? Random()).nextDouble();
  return Duration(milliseconds: (base * 1000 * jitter).round());
}
