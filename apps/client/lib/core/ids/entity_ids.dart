import 'dart:math';

/// Typed ID so a task ID cannot be passed where a project ID is expected.
extension type const TaskId(String value) {}
extension type const ProjectId(String value) {}
extension type const WorkspaceId(String value) {}
extension type const MilestoneId(String value) {}
extension type const MutationId(String value) {}

final _random = Random.secure();

/// Time-sortable UUIDv7 (RFC 9562), generated on the device before any sync.
String newUuid7({DateTime? now}) {
  final ms = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  for (var i = 0; i < 6; i++) {
    b[i] = (ms >> (8 * (5 - i))) & 0xff;
  }
  b[6] = (b[6] & 0x0f) | 0x70;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
