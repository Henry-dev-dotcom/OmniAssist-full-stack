import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/core_tables.dart';
import '../tables/sync_tables.dart';

part 'time_block_dao.g.dart';

@DriftAccessor(tables: [TimeBlocks, Tasks, OutboxMutations])
class TimeBlockDao extends DatabaseAccessor<AppDatabase>
    with _$TimeBlockDaoMixin {
  TimeBlockDao(super.db);

  Future<TimeBlock?> byId(String id) =>
      (select(timeBlocks)..where((b) => b.id.equals(id))).getSingleOrNull();

  /// Blocks that touch [start, end). Includes finished and cancelled blocks.
  Stream<List<TimeBlock>> watchRange(
          String workspaceId, DateTime start, DateTime end) =>
      (select(timeBlocks)
            ..where((b) =>
                b.workspaceId.equals(workspaceId) &
                b.deletedAt.isNull() &
                b.endsAt.isBiggerThanValue(start) &
                b.startsAt.isSmallerThanValue(end))
            ..orderBy([(b) => OrderingTerm.asc(b.startsAt)]))
          .watch();

  Future<List<TimeBlock>> inRange(
          String workspaceId, DateTime start, DateTime end) =>
      watchRange(workspaceId, start, end).first;

  /// Open tasks that have no live time block yet (the "unscheduled" tray).
  Stream<List<Task>> watchUnscheduledTasks(String workspaceId) =>
      (select(tasks)
            ..where((t) =>
                t.workspaceId.equals(workspaceId) &
                t.deletedAt.isNull() &
                t.status.isNotIn(const ['complete', 'cancelled', 'archived']) &
                notExistsQuery(select(timeBlocks)
                  ..where((b) =>
                      b.taskId.equalsExp(t.id) & b.deletedAt.isNull())))
            ..orderBy([(t) => OrderingTerm.asc(t.dueAt)]))
          .watch();

  Future<void> createWithOutbox({
    required String id,
    required String workspaceId,
    required String title,
    required String category,
    required DateTime startsAt,
    required DateTime endsAt,
    String? taskId,
    String? projectId,
    required String mutationId,
    required DateTime now,
  }) =>
      transaction(() async {
        await into(timeBlocks).insert(TimeBlocksCompanion.insert(
          id: id,
          workspaceId: workspaceId,
          title: title,
          category: Value(category),
          startsAt: startsAt,
          endsAt: endsAt,
          taskId: Value(taskId),
          projectId: Value(projectId),
          createdAt: now,
          updatedAt: now,
          syncState: const Value('pending_create'),
        ));
        await _enqueue(mutationId, workspaceId, id, 'create', {
          'title': title,
          'category': category,
          'starts_at': startsAt,
          'ends_at': endsAt,
          'task_id': taskId,
          'project_id': projectId,
        }, null, now);
      });

  /// Applies [changes] (API field names) locally and queues one update.
  Future<void> updateWithOutbox({
    required String id,
    required Map<String, Object?> changes,
    required String mutationId,
    required DateTime now,
  }) =>
      transaction(() async {
        final row = await byId(id);
        if (row == null) return;
        bool has(String k) => changes.containsKey(k);
        await (update(timeBlocks)..where((b) => b.id.equals(id))).write(
          TimeBlocksCompanion(
            title: has('title')
                ? Value(changes['title'] as String)
                : const Value.absent(),
            category: has('category')
                ? Value(changes['category'] as String)
                : const Value.absent(),
            startsAt: has('starts_at')
                ? Value(changes['starts_at'] as DateTime)
                : const Value.absent(),
            endsAt: has('ends_at')
                ? Value(changes['ends_at'] as DateTime)
                : const Value.absent(),
            status: has('status')
                ? Value(changes['status'] as String)
                : const Value.absent(),
            taskId: has('task_id')
                ? Value(changes['task_id'] as String?)
                : const Value.absent(),
            projectId: has('project_id')
                ? Value(changes['project_id'] as String?)
                : const Value.absent(),
            updatedAt: Value(now),
            syncState: Value(row.syncState == 'pending_create'
                ? 'pending_create'
                : 'pending_update'),
          ),
        );
        await _enqueue(mutationId, row.workspaceId, id, 'update', changes,
            row.version, now);
      });

  Future<void> deleteWithOutbox({
    required String id,
    required String mutationId,
    required DateTime now,
  }) =>
      transaction(() async {
        final row = await byId(id);
        if (row == null) return;
        await (update(timeBlocks)..where((b) => b.id.equals(id))).write(
            TimeBlocksCompanion(
                deletedAt: Value(now),
                updatedAt: Value(now),
                syncState: const Value('pending_update')));
        await _enqueue(
            mutationId, row.workspaceId, id, 'delete', {}, row.version, now);
      });

  Future<void> _enqueue(String mutationId, String workspaceId, String id,
      String op, Map<String, Object?> payload, int? base, DateTime now) {
    final wire = {
      for (final e in payload.entries)
        e.key: e.value is DateTime
            ? (e.value as DateTime).toUtc().toIso8601String()
            : e.value,
    };
    return into(outboxMutations).insert(OutboxMutationsCompanion.insert(
      mutationId: mutationId,
      workspaceId: workspaceId,
      entityType: 'time_block',
      entityId: id,
      operation: op,
      payload: jsonEncode(wire),
      baseVersion: Value(base),
      createdAt: now,
    ));
  }
}
