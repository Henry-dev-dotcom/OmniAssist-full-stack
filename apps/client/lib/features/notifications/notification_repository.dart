import 'package:drift/drift.dart';

import '../../core/errors/app_error.dart';
import '../../core/errors/error_codes.dart';
import '../../core/ids/entity_ids.dart';
import '../../core/time/app_clock.dart';
import '../../database/app_database.dart';
import 'notification_gateway.dart';
import 'reminder_rules.dart';

const defaultQuiet = QuietHours(22 * 60, 7 * 60);

/// What each action may start from and where it leads.
const _actions = <String, (Set<String>, String?)>{
  'dismiss': ({'sent', 'snoozed', 'failed'}, 'dismissed'),
  'snooze': ({'sent', 'snoozed'}, 'snoozed'),
  'ack': ({'sent'}, 'acted_on'),
  'read': ({'sent', 'failed', 'dismissed', 'acted_on'}, null),
};

class NotificationRepository {
  NotificationRepository(this._db, this._clock, this._gateway);
  final AppDatabase _db;
  final AppClock _clock;
  final NotificationGateway _gateway;

  Future<bool> osPermitted() => _gateway.isPermitted();

  Stream<List<Reminder>> watchCenter(String ws, {bool unreadOnly = false}) =>
      _db.reminderDao.watchCenter(ws, unreadOnly: unreadOnly);

  Stream<int> watchUnread(String ws) => _db.reminderDao.watchUnreadCount(ws);

  Future<List<Reminder>> forTask(String taskId) =>
      _db.reminderDao.forTask(taskId);

  // ---- quiet hours ----------------------------------------------------------

  Future<QuietHours?> quietHours() async {
    final raw = await _db.reminderDao.setting('quiet_hours');
    if (raw == null) return defaultQuiet;
    return raw == 'off' ? null : QuietHours.parse(raw);
  }

  Future<void> setQuietHours(QuietHours? q) =>
      _db.reminderDao.putSetting('quiet_hours', q?.encoded ?? 'off');

  // ---- scheduling -----------------------------------------------------------

  AppError _rule(String message) =>
      AppError(code: ErrorCode.domainRuleViolation, message: message);

  /// Replaces the task's open reminders. Past times are dropped.
  /// Returns how many reminders were scheduled.
  Future<int> setForTask(
    Task t,
    List<String> specs, {
    String urgency = 'normal',
  }) async {
    if (closedTaskStates.contains(t.status)) {
      throw _rule('A finished task cannot receive new reminders.');
    }
    if (t.dueAt == null && specs.isNotEmpty) {
      throw _rule('Set a due date before adding reminders.');
    }
    for (final s in specs) {
      if (!isValidOffset(s)) {
        throw AppError(
          code: ErrorCode.validationError,
          message: 'Unknown reminder: $s',
        );
      }
    }
    if (!urgencies.contains(urgency)) {
      throw AppError(
        code: ErrorCode.validationError,
        message: 'Unknown urgency: $urgency',
      );
    }
    final quiet = await quietHours();
    final now = _clock.now();
    final rows = <RemindersCompanion>[];
    for (final spec in specs.toSet()) {
      final when = respectQuietHours(remindAt(t.dueAt!, spec), urgency, quiet);
      if (!when.isAfter(now)) continue;
      rows.add(
        RemindersCompanion.insert(
          id: newUuid7(now: now),
          workspaceId: t.workspaceId,
          taskId: t.id,
          title: t.title,
          offsetSpec: spec,
          urgency: Value(urgency),
          remindAt: when,
        ),
      );
    }
    await _db.reminderDao.replaceForTask(t.id, rows);
    return rows.length;
  }

  /// Keeps reminders in step with a task that just changed (Spec 4.5).
  Future<void> syncForTask(Task t) async {
    if (closedTaskStates.contains(t.status) || t.dueAt == null) {
      await _db.reminderDao.cancelForTask(t.id);
      return;
    }
    final open = (await _db.reminderDao.forTask(
      t.id,
      openOnly: true,
    )).where((r) => r.status == 'scheduled').toList();
    if (open.isEmpty) return;
    await setForTask(t, [
      for (final r in open) r.offsetSpec,
    ], urgency: open.first.urgency);
  }

  // ---- delivery ---------------------------------------------------------------

  /// Fires due reminders. Call it on a timer and when the app resumes.
  Future<int> deliverDue() async {
    final now = _clock.now();
    final quiet = await quietHours();
    var sent = 0;
    for (final r in await _db.reminderDao.due(now)) {
      final task = await _db.taskDao.byId(r.taskId);
      if (task == null ||
          task.deletedAt != null ||
          closedTaskStates.contains(task.status)) {
        await _db.reminderDao.patch(
          r.id,
          const RemindersCompanion(status: Value('cancelled')),
        );
        continue;
      }
      final later = respectQuietHours(now, r.urgency, quiet);
      if (later.isAfter(now)) {
        await _db.reminderDao.patch(
          r.id,
          r.status == 'snoozed'
              ? RemindersCompanion(snoozedUntil: Value(later))
              : RemindersCompanion(remindAt: Value(later)),
        );
        continue;
      }
      var status = 'sent';
      String? why;
      try {
        if (await _gateway.isPermitted()) {
          await _gateway.show(id: r.id, title: r.title, urgency: r.urgency);
        }
      } on Object catch (e) {
        status = 'failed';
        why = e.toString();
      }
      await _db.reminderDao.patch(
        r.id,
        RemindersCompanion(
          status: Value(status),
          sentAt: Value(now),
          snoozedUntil: const Value(null),
          readAt: r.status == 'snoozed'
              ? const Value(null)
              : const Value.absent(),
          failureReason: Value(why),
        ),
      );
      sent++;
    }
    return sent;
  }

  // ---- user actions -----------------------------------------------------------

  Future<void> dismiss(String id) => _act(id, 'dismiss');
  Future<void> acknowledge(String id) => _act(id, 'ack');
  Future<void> markRead(String id) => _act(id, 'read');
  Future<void> snooze(String id, {int minutes = 10}) =>
      _act(id, 'snooze', minutes: minutes);

  Future<void> _act(String id, String action, {int minutes = 10}) async {
    final r = await _db.reminderDao.byId(id);
    if (r == null) {
      throw AppError(
        code: ErrorCode.notFound,
        message: 'This reminder no longer exists.',
      );
    }
    final (from, to) = _actions[action]!;
    if (!from.contains(r.status)) {
      throw _rule('A ${r.status} reminder cannot be changed that way.');
    }
    final now = _clock.now();
    final Value<DateTime?> read = r.readAt == null
        ? Value(now)
        : const Value<DateTime?>.absent();
    await _db.reminderDao.patch(id, switch (action) {
      'read' => RemindersCompanion(readAt: read),
      'snooze' => RemindersCompanion(
        status: const Value('snoozed'),
        snoozedUntil: Value(now.add(Duration(minutes: minutes))),
        readAt: read,
      ),
      _ => RemindersCompanion(status: Value(to!), readAt: read),
    });
  }
}
