import '../../core/errors/app_error.dart';
import '../../core/errors/error_codes.dart';
import '../../core/ids/entity_ids.dart';
import '../../core/time/app_clock.dart';
import '../../database/app_database.dart';
import 'time_block_rules.dart';

/// Result of a save: the block ID plus any blocks it overlaps. Overlap is a
/// warning, never an error (Spec 4.4).
class BlockSaved {
  const BlockSaved(this.id, this.overlaps);
  final String id;
  final List<TimeBlock> overlaps;
}

class TimeBlocksRepository {
  TimeBlocksRepository(this._db, this._clock);
  final AppDatabase _db;
  final AppClock _clock;

  Stream<List<TimeBlock>> watchRange(String ws, DateTime start, DateTime end) =>
      _db.timeBlockDao.watchRange(ws, start, end);

  Stream<List<Task>> watchUnscheduled(String ws) =>
      _db.timeBlockDao.watchUnscheduledTasks(ws);

  Future<TimeBlock?> byId(String id) => _db.timeBlockDao.byId(id);

  Future<List<TimeBlock>> overlapsFor(
          String ws, DateTime start, DateTime end, {String? excludeId}) async =>
      overlapping(start, end, await _db.timeBlockDao.inRange(ws, start, end),
          excludeId: excludeId);

  Never _invalid(String message) => throw AppError(
      code: ErrorCode.validationError, message: message);

  Future<BlockSaved> create({
    required String ws,
    required String title,
    required String category,
    required DateTime startsAt,
    required DateTime endsAt,
    String? taskId,
    String? projectId,
  }) async {
    if (title.trim().isEmpty) _invalid('Enter a title.');
    final bad = validateRange(startsAt, endsAt);
    if (bad != null) _invalid(bad);
    final clashes = await overlapsFor(ws, startsAt, endsAt);
    final id = newUuid7(now: _clock.now());
    await _db.timeBlockDao.createWithOutbox(
      id: id,
      workspaceId: ws,
      title: title.trim(),
      category: category,
      startsAt: startsAt.toUtc(),
      endsAt: endsAt.toUtc(),
      taskId: taskId,
      projectId: projectId,
      mutationId: newUuid7(now: _clock.now()),
      now: _clock.now(),
    );
    return BlockSaved(id, clashes);
  }

  /// Moves a block. Works offline: the view updates now and sync follows.
  Future<BlockSaved> reschedule(String id, DateTime startsAt, DateTime endsAt) =>
      edit(id, startsAt: startsAt, endsAt: endsAt);

  /// Saves only the fields that changed. Null arguments mean "leave as is".
  Future<BlockSaved> edit(
    String id, {
    String? title,
    String? category,
    DateTime? startsAt,
    DateTime? endsAt,
    String? status,
  }) async {
    final b = await _db.timeBlockDao.byId(id);
    if (b == null) _invalid('This block no longer exists.');
    final start = (startsAt ?? b.startsAt).toUtc();
    final end = (endsAt ?? b.endsAt).toUtc();
    final bad = validateRange(start, end);
    if (bad != null) _invalid(bad);
    if (title != null && title.trim().isEmpty) _invalid('Enter a title.');
    if (status != null && !canTransition(b.status, status)) {
      throw AppError(
          code: ErrorCode.domainRuleViolation,
          message: 'A ${b.status} block cannot become $status.');
    }
    final changes = <String, Object?>{
      if (title != null && title.trim() != b.title) 'title': title.trim(),
      if (category != null && category != b.category) 'category': category,
      if (start != b.startsAt.toUtc()) 'starts_at': start,
      if (end != b.endsAt.toUtc()) 'ends_at': end,
      if (status != null && status != b.status) 'status': status,
    };
    final clashes = await overlapsFor(b.workspaceId, start, end, excludeId: id);
    if (changes.isNotEmpty) {
      await _db.timeBlockDao.updateWithOutbox(
        id: id,
        changes: changes,
        mutationId: newUuid7(now: _clock.now()),
        now: _clock.now(),
      );
    }
    return BlockSaved(id, clashes);
  }

  Future<void> delete(String id) => _db.timeBlockDao.deleteWithOutbox(
      id: id, mutationId: newUuid7(now: _clock.now()), now: _clock.now());
}
