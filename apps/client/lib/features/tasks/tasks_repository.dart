import 'dart:convert';

import '../../core/ids/entity_ids.dart';
import '../../core/time/app_clock.dart';
import '../../database/app_database.dart';
import '../notifications/notification_repository.dart';
import 'recurrence.dart';

/// Values shown on the edit form. [dueAt] and [projectId] may be null (cleared).
class TaskEdit {
  const TaskEdit({
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.dueAt,
    required this.projectId,
    this.tags,
    this.recurrenceRule,
  });
  final String title;
  final String? description;
  final String status;
  final String priority;
  final DateTime? dueAt;
  final String? projectId;

  /// Null leaves tags or the rule as they are.
  final List<String>? tags;
  final String? recurrenceRule;
}

List<String> tagsOf(Task t) =>
    (jsonDecode(t.tags) as List<dynamic>).map((e) => '$e').toList();

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

  /// A planned task created inside a project, optionally under a milestone.
  Future<String> createIn(
    String ws, {
    required String title,
    required String projectId,
    String? milestoneId,
  }) async {
    final id = newUuid7(now: _clock.now());
    await _db.taskDao.createWithOutbox(
      id: id,
      workspaceId: ws,
      title: title.trim(),
      projectId: projectId,
      milestoneId: milestoneId,
      status: 'planned',
      mutationId: newUuid7(now: _clock.now()),
      now: _clock.now(),
    );
    return id;
  }

  /// Links an existing task to a milestone, or unlinks it with null. A task without a
  /// project joins the milestone's [projectId], so it shows on that project's page.
  Future<void> linkMilestone(
    String id,
    String? milestoneId, {
    String? projectId,
  }) async {
    final task = await _db.taskDao.byId(id);
    await _change(id, {
      'milestone_id': milestoneId,
      if (projectId != null && task?.projectId == null) ...{
        'project_id': projectId,
        if (task?.status == 'inbox') 'status': 'planned',
      },
    });
  }

  /// Completing a recurring task finishes this occurrence only and creates the next
  /// one (Spec 4.3). The rule moves to the new task, so re-ticking never duplicates it.
  Future<void> setDone(String id, bool done) async {
    final task = await _db.taskDao.byId(id);
    final rule = task?.recurrenceRule;
    if (!done || task == null || rule == null || task.dueAt == null) {
      await _change(id, {'status': done ? 'complete' : 'planned'});
      return;
    }
    final next = nextOccurrence(task.dueAt!, parseRule(rule));
    await _change(id, {'status': 'complete', 'recurrence_rule': null});
    await _db.taskDao.createWithOutbox(
      id: newUuid7(now: _clock.now()),
      workspaceId: task.workspaceId,
      title: task.title,
      description: task.description,
      priority: task.priority,
      projectId: task.projectId,
      milestoneId: task.milestoneId,
      parentTaskId: task.parentTaskId,
      tags: tagsOf(task),
      dueAt: next.toUtc(),
      recurrenceRule: rule,
      status: 'planned',
      mutationId: newUuid7(now: _clock.now()),
      now: _clock.now(),
    );
  }

  /// A planned subtask under [parent], in the same project.
  Future<void> addSubtask(Task parent, String title) =>
      _db.taskDao.createWithOutbox(
        id: newUuid7(now: _clock.now()),
        workspaceId: parent.workspaceId,
        title: title.trim(),
        parentTaskId: parent.id,
        projectId: parent.projectId,
        milestoneId: parent.milestoneId,
        status: 'planned',
        mutationId: newUuid7(now: _clock.now()),
        now: _clock.now(),
      );

  Stream<List<Task>> watchSubtasks(Task parent) => _db.taskDao
      .watchActive(parent.workspaceId)
      .map(
        (all) => [
          for (final t in all)
            if (t.parentTaskId == parent.id) t,
        ],
      );

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
      if (e.tags != null &&
          e.tags!.join('\u0000') != tagsOf(before).join('\u0000'))
        'tags': e.tags,
      if (e.recurrenceRule != null &&
          (e.recurrenceRule!.isEmpty ? null : e.recurrenceRule) !=
              before.recurrenceRule)
        'recurrence_rule': e.recurrenceRule!.isEmpty ? null : e.recurrenceRule,
    };
    if (changes.isEmpty) return false;
    await _change(before.id, changes);
    return true;
  }
}
