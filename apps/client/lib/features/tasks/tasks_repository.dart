import '../../core/ids/entity_ids.dart';
import '../../core/time/app_clock.dart';
import '../../database/app_database.dart';
import '../notifications/notification_repository.dart';

/// Values shown on the edit form. [dueAt] and [projectId] may be null (cleared).
class TaskEdit {
  const TaskEdit({
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.dueAt,
    required this.projectId,
  });
  final String title;
  final String? description;
  final String status;
  final String priority;
  final DateTime? dueAt;
  final String? projectId;
}

const taskStatuses = [
  'inbox',
  'planned',
  'in_progress',
  'complete',
  'snoozed',
  'cancelled',
  'archived',
];
const taskPriorities = ['low', 'normal', 'high', 'critical'];

/// A date picked by the user means "by the end of that local day".
DateTime dueFromDate(DateTime d) =>
    DateTime(d.year, d.month, d.day, 23, 59).toUtc();

/// Local-first task access. Writes go to the local database and the outbox.
class TasksRepository {
  TasksRepository(this._db, this._clock, [this._reminders]);
  final AppDatabase _db;
  final AppClock _clock;
  final NotificationRepository? _reminders;

  Stream<List<Task>> watchInbox(String ws) => _db.taskDao.watchInbox(ws);

  /// Overdue and due-today open tasks. "Today" ends at local midnight.
  Stream<List<Task>> watchToday(String ws) {
    final n = _clock.now().toLocal();
    final endOfDay = DateTime(
      n.year,
      n.month,
      n.day + 1,
    ).subtract(const Duration(milliseconds: 1));
    return _db.taskDao.watchDueBy(ws, endOfDay.toUtc());
  }

  /// Quick capture: a title is enough. The task lands in the Inbox.
  Future<void> capture(String ws, String title) => _db.taskDao.createWithOutbox(
    id: newUuid7(now: _clock.now()),
    workspaceId: ws,
    title: title.trim(),
    mutationId: newUuid7(now: _clock.now()),
    now: _clock.now(),
  );

  Future<void> setDone(String id, bool done) =>
      _change(id, {'status': done ? 'complete' : 'planned'});

  /// Moves the due time; reminders follow (Spec 4.5).
  Future<void> reschedule(String id, DateTime? due) =>
      _change(id, {'due_at': due});

  Future<void> archive(String id) => _change(id, {'status': 'archived'});

  /// Inbox item becomes a planned task inside [projectId].
  Future<void> moveToProject(String id, String projectId) =>
      _change(id, {'project_id': projectId, 'status': 'planned'});

  Future<void> _change(String id, Map<String, Object?> changes) async {
    await _db.taskDao.updateWithOutbox(
      id: id,
      changes: changes,
      mutationId: newUuid7(now: _clock.now()),
      now: _clock.now(),
    );
    // Finished, undated or rescheduled tasks must not leave stale reminders behind.
    final task = await _db.taskDao.byId(id);
    if (task != null) await _reminders?.syncForTask(task);
  }

  /// Saves only the fields that differ from [before]. Returns false when nothing changed.
  Future<bool> edit(Task before, TaskEdit e) async {
    final desc = (e.description?.trim().isEmpty ?? true)
        ? null
        : e.description!.trim();
    final changes = <String, Object?>{
      if (e.title.trim() != before.title) 'title': e.title.trim(),
      if (desc != before.description) 'description': desc,
      if (e.status != before.status) 'status': e.status,
      if (e.priority != before.priority) 'priority': e.priority,
      if (e.dueAt != before.dueAt) 'due_at': e.dueAt,
      if (e.projectId != before.projectId) 'project_id': e.projectId,
    };
    if (changes.isEmpty) return false;
    await _change(before.id, changes);
    return true;
  }
}
