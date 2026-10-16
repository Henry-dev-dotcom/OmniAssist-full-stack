import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/record_tables.dart';
import '../tables/sync_tables.dart';

part 'record_dao.g.dart';

/// JSON-safe copy of [values]: DateTimes become UTC ISO strings, the wire format.
Map<String, Object?> wire(Map<String, Object?> values) => {
  for (final e in values.entries)
    e.key: e.value is DateTime
        ? (e.value as DateTime).toUtc().toIso8601String()
        : e.value,
};

/// Generic store for record-backed entities (decision 0003). Each write updates the row
/// and queues its outbox mutation in one transaction (Spec 4.12).
@DriftAccessor(tables: [Records, OutboxMutations])
class RecordDao extends DatabaseAccessor<AppDatabase> with _$RecordDaoMixin {
  RecordDao(super.db);

  SimpleSelectStatement<$RecordsTable, RecordRow> _live(
    String ws,
    String type,
  ) => select(records)
    ..where(
      (r) =>
          r.workspaceId.equals(ws) &
          r.entityType.equals(type) &
          r.deletedAt.isNull(),
    );

  Stream<List<RecordRow>> watchType(String ws, String type) => (_live(
    ws,
    type,
  )..orderBy([(r) => OrderingTerm.asc(r.createdAt)])).watch();

  Future<List<RecordRow>> ofType(String ws, String type) =>
      (_live(ws, type)..orderBy([(r) => OrderingTerm.asc(r.createdAt)])).get();

  /// Every live record in the workspace, for search and export.
  Future<List<RecordRow>> allLive(String ws) => (select(
    records,
  )..where((r) => r.workspaceId.equals(ws) & r.deletedAt.isNull())).get();

  Future<RecordRow?> byId(String id) =>
      (select(records)..where((r) => r.id.equals(id))).getSingleOrNull();

  Stream<RecordRow?> watchById(String id) =>
      (select(records)..where((r) => r.id.equals(id))).watchSingleOrNull();

  /// Creates several records and their mutations atomically: all or none (CSV import).
  Future<void> createAll(
    String ws,
    List<
      ({String type, String id, Map<String, Object?> data, String mutationId})
    >
    rows,
    DateTime now,
  ) => transaction(() async {
    for (final r in rows) {
      final body = wire(r.data);
      await into(records).insert(
        RecordsCompanion.insert(
          id: r.id,
          workspaceId: ws,
          entityType: r.type,
          data: jsonEncode(body),
          createdAt: now,
          updatedAt: now,
          syncState: const Value('pending_create'),
        ),
      );
      await into(outboxMutations).insert(
        OutboxMutationsCompanion.insert(
          mutationId: r.mutationId,
          workspaceId: ws,
          entityType: r.type,
          entityId: r.id,
          operation: 'create',
          payload: jsonEncode(body),
          createdAt: now,
        ),
      );
    }
  });

  Future<void> create(
    String ws,
    String type,
    String id,
    Map<String, Object?> data,
    String mutationId,
    DateTime now,
  ) => createAll(ws, [
    (type: type, id: id, data: data, mutationId: mutationId),
  ], now);

  /// Merges [changes] into the record and queues one update mutation.
  Future<void> change(
    String id,
    Map<String, Object?> changes,
    String mutationId,
    DateTime now,
  ) => transaction(() async {
    final row = await byId(id);
    if (row == null || changes.isEmpty) return;
    final body = wire(changes);
    final data = {...jsonDecode(row.data) as Map<String, dynamic>, ...body};
    await (update(records)..where((r) => r.id.equals(id))).write(
      RecordsCompanion(
        data: Value(jsonEncode(data)),
        updatedAt: Value(now),
        syncState: Value(
          row.syncState == 'pending_create'
              ? 'pending_create'
              : 'pending_update',
        ),
      ),
    );
    await into(outboxMutations).insert(
      OutboxMutationsCompanion.insert(
        mutationId: mutationId,
        workspaceId: row.workspaceId,
        entityType: row.entityType,
        entityId: id,
        operation: 'update',
        payload: jsonEncode(body),
        baseVersion: Value(row.version),
        createdAt: now,
      ),
    );
  });

  /// Hides the record now and queues a delete; the server keeps a tombstone.
  Future<void> remove(String id, String mutationId, DateTime now) =>
      transaction(() async {
        final row = await byId(id);
        if (row == null) return;
        await (update(records)..where((r) => r.id.equals(id))).write(
          RecordsCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
            syncState: const Value('pending_delete'),
          ),
        );
        await into(outboxMutations).insert(
          OutboxMutationsCompanion.insert(
            mutationId: mutationId,
            workspaceId: row.workspaceId,
            entityType: row.entityType,
            entityId: id,
            operation: 'delete',
            payload: '{}',
            baseVersion: Value(row.version),
            createdAt: now,
          ),
        );
      });
}
