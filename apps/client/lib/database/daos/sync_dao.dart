import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/core_tables.dart';
import '../tables/record_tables.dart';
import '../tables/sync_tables.dart';

part 'sync_dao.g.dart';

@DriftAccessor(
  tables: [
    SyncState,
    OutboxMutations,
    ConflictRecords,
    Projects,
    Tasks,
    TimeBlocks,
    Records,
  ],
)
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  Future<List<OutboxMutation>> pending({int limit = 50}) =>
      (select(outboxMutations)
            ..where((m) => m.status.equals('pending'))
            ..orderBy([(m) => OrderingTerm.asc(m.createdAt)])
            ..limit(limit))
          .get();

  /// Pending mutations whose retry time has arrived, oldest first.
  Future<List<OutboxMutation>> due(DateTime now, {int limit = 50}) =>
      (select(outboxMutations)
            ..where(
              (m) =>
                  m.status.equals('pending') &
                  (m.nextAttemptAt.isNull() |
                      m.nextAttemptAt.isSmallerOrEqualValue(now)),
            )
            ..orderBy([(m) => OrderingTerm.asc(m.createdAt)])
            ..limit(limit))
          .get();

  Stream<int> watchPendingCount() =>
      (select(outboxMutations)..where((m) => m.status.equals('pending')))
          .watch()
          .map((rows) => rows.length);

  Stream<int> watchOpenConflictCount() => (select(
    conflictRecords,
  )..where((c) => c.status.equals('open'))).watch().map((rows) => rows.length);

  Future<int> cursorFor(String deviceId) async {
    final row = await (select(
      syncState,
    )..where((s) => s.deviceId.equals(deviceId))).getSingleOrNull();
    return row?.cursor ?? 0;
  }

  /// This device's ID, or null before the first sync.
  Future<String?> existingDeviceId() async =>
      (await select(syncState).get()).firstOrNull?.deviceId;

  /// Creates the row on first use. A different account on the same device starts
  /// again from cursor 0 so it never skips another account's history.
  Future<void> ensureState(String deviceId, String accountId) async {
    final row = await (select(
      syncState,
    )..where((s) => s.deviceId.equals(deviceId))).getSingleOrNull();
    if (row == null) {
      await into(syncState).insert(
        SyncStateCompanion.insert(deviceId: deviceId, accountId: accountId),
      );
    } else if (row.accountId != accountId) {
      await (update(
        syncState,
      )..where((s) => s.deviceId.equals(deviceId))).write(
        SyncStateCompanion(accountId: Value(accountId), cursor: const Value(0)),
      );
    }
  }

  Future<void> setStatus(String deviceId, String status, {DateTime? at}) =>
      (update(syncState)..where((s) => s.deviceId.equals(deviceId))).write(
        SyncStateCompanion(
          status: Value(status),
          lastSyncAt: at == null ? const Value.absent() : Value(at),
        ),
      );

  /// Records a failed attempt for every mutation in a batch.
  Future<void> markAttemptFailed(
    List<OutboxMutation> batch,
    String code,
    DateTime next,
  ) async {
    for (final m in batch) {
      await (update(
        outboxMutations,
      )..where((x) => x.mutationId.equals(m.mutationId))).write(
        OutboxMutationsCompanion(
          attemptCount: Value(m.attemptCount + 1),
          nextAttemptAt: Value(next),
          lastErrorCode: Value(code),
        ),
      );
    }
  }

  /// Applies one server verdict for [m]. Everything in one transaction.
  Future<void> applyPushResult(
    OutboxMutation m,
    Map<String, dynamic> result,
    DateTime now,
  ) {
    return transaction(() async {
      final status = result['status'] as String;
      final out = update(outboxMutations)
        ..where((x) => x.mutationId.equals(m.mutationId));
      String entityState;
      switch (status) {
        case 'accepted':
          await (delete(
            outboxMutations,
          )..where((x) => x.mutationId.equals(m.mutationId))).go();
          final more =
              await (select(outboxMutations)..where(
                    (x) =>
                        x.entityId.equals(m.entityId) &
                        x.status.equals('pending'),
                  ))
                  .get();
          entityState = more.isEmpty ? 'synced' : 'pending_update';
          await _bumpVersion(
            m.entityType,
            m.entityId,
            result['entity_version'] as int?,
          );
        case 'conflict':
          await out.write(
            const OutboxMutationsCompanion(status: Value('conflict')),
          );
          await into(conflictRecords).insertOnConflictUpdate(
            ConflictRecordsCompanion.insert(
              id: (result['conflict_id'] as String?) ?? m.mutationId,
              entityType: m.entityType,
              entityId: m.entityId,
              localJson: m.payload,
              serverJson: jsonEncode(result['server'] ?? {}),
              createdAt: now,
            ),
          );
          entityState = 'conflict';
        default: // rejected
          await out.write(
            OutboxMutationsCompanion(
              status: const Value('rejected'),
              lastErrorCode: Value(result['error_code'] as String?),
            ),
          );
          entityState = 'rejected';
      }
      switch (m.entityType) {
        case 'project':
          await (update(projects)..where((p) => p.id.equals(m.entityId))).write(
            ProjectsCompanion(syncState: Value(entityState)),
          );
        case 'task':
          await (update(tasks)..where((t) => t.id.equals(m.entityId))).write(
            TasksCompanion(syncState: Value(entityState)),
          );
        case 'time_block':
          await (update(timeBlocks)..where((b) => b.id.equals(m.entityId)))
              .write(TimeBlocksCompanion(syncState: Value(entityState)));
        default:
          await (update(records)..where((r) => r.id.equals(m.entityId))).write(
            RecordsCompanion(syncState: Value(entityState)),
          );
      }
    });
  }

  Future<void> _bumpVersion(String type, String id, int? v) async {
    if (v == null) return;
    switch (type) {
      case 'project':
        final row = await (select(
          projects,
        )..where((p) => p.id.equals(id))).getSingleOrNull();
        if (row != null && v > row.version) {
          await (update(projects)..where((p) => p.id.equals(id))).write(
            ProjectsCompanion(version: Value(v)),
          );
        }
      case 'task':
        final row = await (select(
          tasks,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (row != null && v > row.version) {
          await (update(tasks)..where((t) => t.id.equals(id))).write(
            TasksCompanion(version: Value(v)),
          );
        }
      case 'time_block':
        final row = await (select(
          timeBlocks,
        )..where((b) => b.id.equals(id))).getSingleOrNull();
        if (row != null && v > row.version) {
          await (update(timeBlocks)..where((b) => b.id.equals(id))).write(
            TimeBlocksCompanion(version: Value(v)),
          );
        }
      default:
        final row = await (select(
          records,
        )..where((r) => r.id.equals(id))).getSingleOrNull();
        if (row != null && v > row.version) {
          await (update(records)..where((r) => r.id.equals(id))).write(
            RecordsCompanion(version: Value(v)),
          );
        }
    }
  }

  Future<Set<String>> _pendingKeys(String entityId) async {
    final rows =
        await (select(outboxMutations)..where(
              (x) =>
                  x.entityId.equals(entityId) &
                  x.status.equals('pending') &
                  // A server update proves it has the create; only real edits win.
                  x.operation.equals('update'),
            ))
            .get();
    return {
      for (final r in rows)
        ...(jsonDecode(r.payload) as Map<String, dynamic>).keys,
    };
  }

  /// Applies one pulled page and stores its cursor in the same transaction, so a
  /// crash can never leave the cursor ahead of the data (sync_protocol.md).
  Future<void> applyPulledPage({
    required String deviceId,
    required List<Map<String, dynamic>> changes,
    required int nextCursor,
    required DateTime now,
  }) {
    return transaction(() async {
      for (final c in changes) {
        switch (c['entity_type']) {
          case 'project':
            await _applyProjectChange(c, now);
          case 'task':
            await _applyTaskChange(c, now);
          case 'time_block':
            await _applyTimeBlockChange(c, now);
          default:
            await _applyRecordChange(c, now);
        }
      }
      await (update(syncState)..where((s) => s.deviceId.equals(deviceId)))
          .write(SyncStateCompanion(cursor: Value(nextCursor)));
    });
  }

  Future<void> _applyProjectChange(Map<String, dynamic> c, DateTime now) async {
    final id = c['entity_id'] as String;
    final op = c['operation'] as String;
    final version = c['entity_version'] as int;
    final local = await (select(
      projects,
    )..where((p) => p.id.equals(id))).getSingleOrNull();

    if (op == 'delete') {
      if (local != null) {
        await (update(projects)..where((p) => p.id.equals(id))).write(
          ProjectsCompanion(
            deletedAt: Value(now),
            version: Value(version),
            syncState: const Value('synced'),
          ),
        );
      }
      return;
    }
    final payload = (c['payload'] as Map<String, dynamic>?) ?? const {};
    if (local == null) {
      final at = DateTime.parse(
        (payload['updated_at'] as String?) ?? now.toIso8601String(),
      );
      await into(projects).insert(
        ProjectsCompanion.insert(
          id: id,
          workspaceId: c['workspace_id'] as String,
          name: (payload['name'] as String?) ?? 'Untitled',
          category: (payload['category'] as String?) ?? 'personal',
          createdAt: at,
          updatedAt: at,
        ),
      );
    }
    // Fields with unsent local edits stay as the user left them; the push decides.
    final blocked = await _pendingKeys(id);
    bool ok(String k) => payload.containsKey(k) && !blocked.contains(k);
    final current = local?.version ?? 0;
    await (update(projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(
        name: ok('name')
            ? Value(payload['name'] as String)
            : const Value.absent(),
        category: ok('category')
            ? Value(payload['category'] as String)
            : const Value.absent(),
        status: ok('status')
            ? Value(payload['status'] as String)
            : const Value.absent(),
        description: ok('description')
            ? Value(payload['description'] as String?)
            : const Value.absent(),
        progressValue: ok('progress_value')
            ? Value((payload['progress_value'] as num).round())
            : const Value.absent(),
        version: Value(version > current ? version : current),
        updatedAt: Value(now),
      ),
    );
  }

  static DateTime? _dt(Object? v) =>
      v == null ? null : DateTime.parse(v as String);

  Future<void> _applyTaskChange(Map<String, dynamic> c, DateTime now) async {
    final id = c['entity_id'] as String;
    final op = c['operation'] as String;
    final version = c['entity_version'] as int;
    final local = await (select(
      tasks,
    )..where((t) => t.id.equals(id))).getSingleOrNull();

    if (op == 'delete') {
      if (local != null) {
        await (update(tasks)..where((t) => t.id.equals(id))).write(
          TasksCompanion(
            deletedAt: Value(now),
            version: Value(version),
            syncState: const Value('synced'),
          ),
        );
      }
      return;
    }
    final payload = (c['payload'] as Map<String, dynamic>?) ?? const {};
    if (local == null) {
      final at = DateTime.parse(
        (payload['updated_at'] as String?) ?? now.toIso8601String(),
      );
      await into(tasks).insert(
        TasksCompanion.insert(
          id: id,
          workspaceId: c['workspace_id'] as String,
          title: (payload['title'] as String?) ?? 'Untitled',
          createdAt: at,
          updatedAt: at,
        ),
      );
    }
    final blocked = await _pendingKeys(id);
    bool ok(String k) => payload.containsKey(k) && !blocked.contains(k);
    final current = local?.version ?? 0;
    await (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        title: ok('title')
            ? Value(payload['title'] as String)
            : const Value.absent(),
        description: ok('description')
            ? Value(payload['description'] as String?)
            : const Value.absent(),
        status: ok('status')
            ? Value(payload['status'] as String)
            : const Value.absent(),
        priority: ok('priority')
            ? Value(payload['priority'] as String)
            : const Value.absent(),
        projectId: ok('project_id')
            ? Value(payload['project_id'] as String?)
            : const Value.absent(),
        milestoneId: ok('milestone_id')
            ? Value(payload['milestone_id'] as String?)
            : const Value.absent(),
        parentTaskId: ok('parent_task_id')
            ? Value(payload['parent_task_id'] as String?)
            : const Value.absent(),
        dueAt: ok('due_at')
            ? Value(_dt(payload['due_at']))
            : const Value.absent(),
        estimatedMinutes: ok('estimated_minutes')
            ? Value(payload['estimated_minutes'] as int?)
            : const Value.absent(),
        recurrenceRule: ok('recurrence_rule')
            ? Value(payload['recurrence_rule'] as String?)
            : const Value.absent(),
        completedAt: ok('completed_at')
            ? Value(_dt(payload['completed_at']))
            : const Value.absent(),
        version: Value(version > current ? version : current),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> _applyTimeBlockChange(
    Map<String, dynamic> c,
    DateTime now,
  ) async {
    final id = c['entity_id'] as String;
    final op = c['operation'] as String;
    final version = c['entity_version'] as int;
    final local = await (select(
      timeBlocks,
    )..where((b) => b.id.equals(id))).getSingleOrNull();

    if (op == 'delete') {
      if (local != null) {
        await (update(timeBlocks)..where((b) => b.id.equals(id))).write(
          TimeBlocksCompanion(
            deletedAt: Value(now),
            version: Value(version),
            syncState: const Value('synced'),
          ),
        );
      }
      return;
    }
    final payload = (c['payload'] as Map<String, dynamic>?) ?? const {};
    if (local == null) {
      final at = DateTime.parse(
        (payload['updated_at'] as String?) ?? now.toIso8601String(),
      );
      await into(timeBlocks).insert(
        TimeBlocksCompanion.insert(
          id: id,
          workspaceId: c['workspace_id'] as String,
          title: (payload['title'] as String?) ?? 'Untitled',
          startsAt: _dt(payload['starts_at']) ?? now,
          endsAt: _dt(payload['ends_at']) ?? now.add(const Duration(hours: 1)),
          createdAt: at,
          updatedAt: at,
        ),
      );
    }
    final blocked = await _pendingKeys(id);
    bool ok(String k) => payload.containsKey(k) && !blocked.contains(k);
    final current = local?.version ?? 0;
    await (update(timeBlocks)..where((b) => b.id.equals(id))).write(
      TimeBlocksCompanion(
        title: ok('title')
            ? Value(payload['title'] as String)
            : const Value.absent(),
        category: ok('category')
            ? Value(payload['category'] as String)
            : const Value.absent(),
        startsAt: ok('starts_at')
            ? Value(_dt(payload['starts_at'])!)
            : const Value.absent(),
        endsAt: ok('ends_at')
            ? Value(_dt(payload['ends_at'])!)
            : const Value.absent(),
        status: ok('status')
            ? Value(payload['status'] as String)
            : const Value.absent(),
        taskId: ok('task_id')
            ? Value(payload['task_id'] as String?)
            : const Value.absent(),
        projectId: ok('project_id')
            ? Value(payload['project_id'] as String?)
            : const Value.absent(),
        version: Value(version > current ? version : current),
        updatedAt: Value(now),
      ),
    );
  }

  /// Record-backed entities merge per field like typed ones: keys with unsent local
  /// edits keep the local value until the push settles them.
  Future<void> _applyRecordChange(Map<String, dynamic> c, DateTime now) async {
    final id = c['entity_id'] as String;
    final version = c['entity_version'] as int;
    final local = await (select(
      records,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (c['operation'] == 'delete') {
      if (local != null) {
        await (update(records)..where((r) => r.id.equals(id))).write(
          RecordsCompanion(
            deletedAt: Value(now),
            version: Value(version),
            syncState: const Value('synced'),
          ),
        );
      }
      return;
    }
    final payload = (c['payload'] as Map<String, dynamic>?) ?? const {};
    if (local == null) {
      final at =
          DateTime.tryParse(
            (payload['updated_at'] ?? payload['created_at'] ?? '') as String,
          ) ??
          now;
      await into(records).insert(
        RecordsCompanion.insert(
          id: id,
          workspaceId: c['workspace_id'] as String,
          entityType: c['entity_type'] as String,
          data: jsonEncode(payload),
          version: Value(version),
          createdAt: at,
          updatedAt: at,
        ),
      );
      return;
    }
    final blocked = await _pendingKeys(id);
    final data = jsonDecode(local.data) as Map<String, dynamic>;
    for (final e in payload.entries) {
      if (!blocked.contains(e.key)) data[e.key] = e.value;
    }
    await (update(records)..where((r) => r.id.equals(id))).write(
      RecordsCompanion(
        data: Value(jsonEncode(data)),
        version: Value(version > local.version ? version : local.version),
        updatedAt: Value(now),
      ),
    );
  }

  Stream<List<ConflictRecord>> watchOpenConflicts() =>
      (select(conflictRecords)
            ..where((c) => c.status.equals('open'))
            ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]))
          .watch();

  /// Uploads the server refused; they wait for the user to retry or discard them.
  Stream<List<OutboxMutation>> watchRejected() =>
      (select(outboxMutations)
            ..where((m) => m.status.equals('rejected'))
            ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
          .watch();

  Future<void> retryRejected(String mutationId) =>
      (update(
        outboxMutations,
      )..where((m) => m.mutationId.equals(mutationId))).write(
        const OutboxMutationsCompanion(
          status: Value('pending'),
          attemptCount: Value(0),
          nextAttemptAt: Value(null),
        ),
      );

  Future<void> discardRejected(String mutationId) => (delete(
    outboxMutations,
  )..where((m) => m.mutationId.equals(mutationId))).go();

  /// Settles a conflict in one transaction (Spec 4.12): [server] values are applied
  /// here, and [local] values go up as a new mutation based on the server's version.
  Future<void> resolveConflict({
    required ConflictRecord conflict,
    required Map<String, Object?> local,
    required Map<String, Object?> server,
    required int serverVersion,
    required String mutationId,
    required DateTime now,
  }) => transaction(() async {
    final stuck =
        await (select(outboxMutations)..where(
              (m) =>
                  m.entityId.equals(conflict.entityId) &
                  m.status.equals('conflict'),
            ))
            .get();
    final serverJson = jsonDecode(conflict.serverJson) as Map<String, dynamic>;
    final ws =
        stuck.firstOrNull?.workspaceId ?? serverJson['workspace_id'] as String;
    Future<void> apply(Map<String, Object?> payload) async {
      final change = {
        'entity_type': conflict.entityType,
        'entity_id': conflict.entityId,
        'workspace_id': ws,
        'operation': 'update',
        'entity_version': serverVersion,
        'payload': payload,
      };
      switch (conflict.entityType) {
        case 'project':
          await _applyProjectChange(change, now);
        case 'task':
          await _applyTaskChange(change, now);
        case 'time_block':
          await _applyTimeBlockChange(change, now);
        default:
          await _applyRecordChange(change, now);
      }
    }

    await (delete(outboxMutations)..where(
          (m) =>
              m.entityId.equals(conflict.entityId) &
              m.status.equals('conflict'),
        ))
        .go();
    await apply({...server, ...local});
    if (local.isNotEmpty) {
      await into(outboxMutations).insert(
        OutboxMutationsCompanion.insert(
          mutationId: mutationId,
          workspaceId: ws,
          entityType: conflict.entityType,
          entityId: conflict.entityId,
          operation: 'update',
          payload: jsonEncode(local),
          baseVersion: Value(serverVersion),
          createdAt: now,
        ),
      );
    }
    await (update(
      conflictRecords,
    )..where((c) => c.id.equals(conflict.id))).write(
      ConflictRecordsCompanion(
        status: const Value('resolved'),
        resolvedAt: Value(now),
      ),
    );
    final state = local.isEmpty ? 'synced' : 'pending_update';
    switch (conflict.entityType) {
      case 'project':
        await (update(projects)..where((p) => p.id.equals(conflict.entityId)))
            .write(ProjectsCompanion(syncState: Value(state)));
      case 'task':
        await (update(tasks)..where((t) => t.id.equals(conflict.entityId)))
            .write(TasksCompanion(syncState: Value(state)));
      case 'time_block':
        await (update(timeBlocks)..where((b) => b.id.equals(conflict.entityId)))
            .write(TimeBlocksCompanion(syncState: Value(state)));
      default:
        await (update(records)..where((r) => r.id.equals(conflict.entityId)))
            .write(RecordsCompanion(syncState: Value(state)));
    }
  });
}
