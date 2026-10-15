import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/core_tables.dart';
import '../tables/sync_tables.dart';

part 'task_dao.g.dart';

@DriftAccessor(tables: [Tasks, OutboxMutations])
class TaskDao extends DatabaseAccessor<AppDatabase> with _$TaskDaoMixin {
  TaskDao(super.db);

  Stream<List<Task>> watchActive(String workspaceId) =>
      (select(tasks)
            ..where(
              (t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull(),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.dueAt)]))
          .watch();

  Future<Task?> byId(String id) =>
      (select(tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Writes the task and its outbox mutation in one transaction. If either insert
  /// fails, neither is kept (Spec 4.12: no partial entity or outbox state).
  Future<void> createWithOutbox({
    required String id,
    required String workspaceId,
    required String title,
    required String mutationId,
    required DateTime now,
  }) => transaction(() async {
    await into(tasks).insert(
      TasksCompanion.insert(
        id: id,
        workspaceId: workspaceId,
        title: title,
        createdAt: now,
        updatedAt: now,
        syncState: const Value('pending_create'),
      ),
    );
    await into(outboxMutations).insert(
      OutboxMutationsCompanion.insert(
        mutationId: mutationId,
        workspaceId: workspaceId,
        entityType: 'task',
        entityId: id,
        operation: 'create',
        payload: jsonEncode({'title': title}),
        createdAt: now,
      ),
    );
  });

  Stream<List<Task>> watchInbox(String workspaceId) =>
      (select(tasks)
            ..where(
              (t) =>
                  t.workspaceId.equals(workspaceId) &
                  t.deletedAt.isNull() &
                  t.status.equals('inbox'),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  /// Open work due on or before [end] (overdue plus today), earliest first.
  Stream<List<Task>> watchDueBy(String workspaceId, DateTime end) =>
      (select(tasks)
            ..where(
              (t) =>
                  t.workspaceId.equals(workspaceId) &
                  t.deletedAt.isNull() &
                  t.status.isNotIn(const [
                    'complete',
                    'cancelled',
                    'archived',
                  ]) &
                  t.dueAt.isSmallerOrEqualValue(end),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.dueAt)]))
          .watch();

  /// Applies [changes] (API field names) locally and queues one mutation, in one
  /// transaction. Setting `status` also sets or clears the completion time.
  Future<void> updateWithOutbox({
    required String id,
    required Map<String, Object?> changes,
    required String mutationId,
    required DateTime now,
  }) => transaction(() async {
    final row = await byId(id);
    if (row == null) return;
    bool has(String k) => changes.containsKey(k);
    final status = changes['status'] as String?;
    await (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        title: has('title')
            ? Value(changes['title'] as String)
            : const Value.absent(),
        description: has('description')
            ? Value(changes['description'] as String?)
            : const Value.absent(),
        status: status != null ? Value(status) : const Value.absent(),
        priority: has('priority')
            ? Value(changes['priority'] as String)
            : const Value.absent(),
        projectId: has('project_id')
            ? Value(changes['project_id'] as String?)
            : const Value.absent(),
        milestoneId: has('milestone_id')
            ? Value(changes['milestone_id'] as String?)
            : const Value.absent(),
        dueAt: has('due_at')
            ? Value(changes['due_at'] as DateTime?)
            : const Value.absent(),
        completedAt: status != null
            ? Value(status == 'complete' ? now : null)
            : const Value.absent(),
        updatedAt: Value(now),
        syncState: Value(
          row.syncState == 'pending_create'
              ? 'pending_create'
              : 'pending_update',
        ),
      ),
    );
    final wire = {
      for (final e in changes.entries)
        e.key: e.value is DateTime
            ? (e.value as DateTime).toUtc().toIso8601String()
            : e.value,
    };
    await into(outboxMutations).insert(
      OutboxMutationsCompanion.insert(
        mutationId: mutationId,
        workspaceId: row.workspaceId,
        entityType: 'task',
        entityId: id,
        operation: 'update',
        payload: jsonEncode(wire),
        baseVersion: Value(row.version),
        createdAt: now,
      ),
    );
  });
}
