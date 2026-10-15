import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/core_tables.dart';
import '../tables/sync_tables.dart';

part 'project_dao.g.dart';

@DriftAccessor(tables: [Projects, OutboxMutations])
class ProjectDao extends DatabaseAccessor<AppDatabase> with _$ProjectDaoMixin {
  ProjectDao(super.db);

  Stream<List<Project>> watchActive(String workspaceId) =>
      (select(projects)
            ..where(
              (p) =>
                  p.workspaceId.equals(workspaceId) &
                  p.deletedAt.isNull() &
                  p.status.equals('archived').not(),
            )
            ..orderBy([(p) => OrderingTerm.asc(p.name)]))
          .watch();

  Stream<List<Project>> watchArchived(String workspaceId) =>
      (select(projects)
            ..where(
              (p) =>
                  p.workspaceId.equals(workspaceId) &
                  p.deletedAt.isNull() &
                  p.status.equals('archived'),
            )
            ..orderBy([(p) => OrderingTerm.asc(p.name)]))
          .watch();

  Future<Project?> byId(String id) =>
      (select(projects)..where((p) => p.id.equals(id))).getSingleOrNull();

  /// Project row and outbox mutation commit together or not at all.
  Future<void> createWithOutbox({
    required String id,
    required String workspaceId,
    required String name,
    required String category,
    required String mutationId,
    required DateTime now,
  }) => transaction(() async {
    await into(projects).insert(
      ProjectsCompanion.insert(
        id: id,
        workspaceId: workspaceId,
        name: name,
        category: category,
        createdAt: now,
        updatedAt: now,
        syncState: const Value('pending_create'),
      ),
    );
    await _enqueue(
      mutationId,
      workspaceId,
      id,
      'create',
      {'name': name, 'category': category},
      null,
      now,
    );
  });

  /// Applies [changes] (API field names: name, status, description, progress_value)
  /// locally and queues one update mutation, in one transaction.
  Future<void> updateWithOutbox({
    required String id,
    required Map<String, Object?> changes,
    required String mutationId,
    required DateTime now,
  }) => transaction(() async {
    final row = await byId(id);
    if (row == null || changes.isEmpty) return;
    bool has(String k) => changes.containsKey(k);
    await (update(projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(
        name: has('name')
            ? Value(changes['name'] as String)
            : const Value.absent(),
        status: has('status')
            ? Value(changes['status'] as String)
            : const Value.absent(),
        description: has('description')
            ? Value(changes['description'] as String?)
            : const Value.absent(),
        progressValue: has('progress_value')
            ? Value(changes['progress_value'] as int)
            : const Value.absent(),
        updatedAt: Value(now),
        syncState: Value(
          row.syncState == 'pending_create'
              ? 'pending_create'
              : 'pending_update',
        ),
      ),
    );
    await _enqueue(
      mutationId,
      row.workspaceId,
      id,
      'update',
      changes,
      row.version,
      now,
    );
  });

  Future<void> deleteWithOutbox({
    required String id,
    required String mutationId,
    required DateTime now,
  }) => transaction(() async {
    final row = await byId(id);
    if (row == null) return;
    await (update(projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncState: const Value('pending_delete'),
      ),
    );
    await _enqueue(
      mutationId,
      row.workspaceId,
      id,
      'delete',
      const {},
      row.version,
      now,
    );
  });

  Stream<Project?> watchById(String id) =>
      (select(projects)..where((p) => p.id.equals(id))).watchSingleOrNull();

  /// Applies server rows. A row with unsent local edits is never overwritten;
  /// conflicts are the sync engine's job.
  Future<void> upsertFromServer(List<ProjectsCompanion> rows) =>
      transaction(() async {
        for (final r in rows) {
          final local = await byId(r.id.value);
          if (local != null && local.syncState != 'synced') continue;
          await into(projects).insertOnConflictUpdate(r);
        }
      });

  Future<void> _enqueue(
    String mutationId,
    String workspaceId,
    String id,
    String op,
    Map<String, Object?> payload,
    int? base,
    DateTime now,
  ) => into(outboxMutations).insert(
    OutboxMutationsCompanion.insert(
      mutationId: mutationId,
      workspaceId: workspaceId,
      entityType: 'project',
      entityId: id,
      operation: op,
      payload: jsonEncode(payload),
      baseVersion: Value(base),
      createdAt: now,
    ),
  );
}
