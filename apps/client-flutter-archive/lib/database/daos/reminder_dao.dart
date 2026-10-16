import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/reminder_tables.dart';

part 'reminder_dao.g.dart';

const openStatuses = ['scheduled', 'snoozed'];

@DriftAccessor(tables: [Reminders, LocalSettings])
class ReminderDao extends DatabaseAccessor<AppDatabase>
    with _$ReminderDaoMixin {
  ReminderDao(super.db);

  Future<Reminder?> byId(String id) =>
      (select(reminders)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<List<Reminder>> forTask(String taskId, {bool openOnly = false}) =>
      (select(reminders)
            ..where(
              (r) =>
                  r.taskId.equals(taskId) &
                  (openOnly
                      ? r.status.isIn(openStatuses)
                      : r.status.isNotValue('cancelled')),
            )
            ..orderBy([(r) => OrderingTerm.asc(r.remindAt)]))
          .get();

  Future<int> cancelForTask(String taskId) =>
      (update(reminders)..where(
            (r) => r.taskId.equals(taskId) & r.status.isIn(openStatuses),
          ))
          .write(const RemindersCompanion(status: Value('cancelled')));

  /// Cancels the task's open reminders and stores [rows] in one step.
  Future<void> replaceForTask(String taskId, List<RemindersCompanion> rows) =>
      transaction(() async {
        await cancelForTask(taskId);
        for (final r in rows) {
          await into(reminders).insert(r);
        }
      });

  Future<List<Reminder>> due(DateTime now) =>
      (select(reminders)
            ..where(
              (r) =>
                  (r.status.equals('scheduled') &
                      r.remindAt.isSmallerOrEqualValue(now)) |
                  (r.status.equals('snoozed') &
                      r.snoozedUntil.isSmallerOrEqualValue(now)),
            )
            ..orderBy([(r) => OrderingTerm.asc(r.remindAt)]))
          .get();

  /// What the notification center shows: everything that has fired or is snoozed.
  Stream<List<Reminder>> watchCenter(String ws, {bool unreadOnly = false}) =>
      (select(reminders)
            ..where(
              (r) =>
                  r.workspaceId.equals(ws) &
                  r.status.isIn([
                    'sent',
                    'snoozed',
                    'failed',
                    'dismissed',
                    'acted_on',
                  ]) &
                  (unreadOnly ? r.readAt.isNull() : const Constant(true)),
            )
            ..orderBy([(r) => OrderingTerm.desc(r.remindAt)]))
          .watch();

  Stream<int> watchUnreadCount(String ws) {
    final n = reminders.id.count();
    return (selectOnly(reminders)
          ..addColumns([n])
          ..where(
            reminders.workspaceId.equals(ws) &
                reminders.status.isIn(['sent', 'failed']) &
                reminders.readAt.isNull(),
          ))
        .map((row) => row.read(n) ?? 0)
        .watchSingle();
  }

  Future<void> patch(String id, RemindersCompanion c) =>
      (update(reminders)..where((r) => r.id.equals(id))).write(c);

  Future<String?> setting(String key) async => (await (select(
    localSettings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<void> putSetting(String key, String value) => into(localSettings)
      .insertOnConflictUpdate(
        LocalSettingsCompanion.insert(key: key, value: value),
      );
}
