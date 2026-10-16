import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/ids/entity_ids.dart';
import '../../core/time/app_clock.dart';
import '../../database/app_database.dart';
import '../auth/auth_controller.dart';

/// Read view over one record-backed entity (decision 0003). Field names follow the API.
class Rec {
  Rec(this.row) : data = jsonDecode(row.data) as Map<String, dynamic>;
  final RecordRow row;
  final Map<String, dynamic> data;

  String get id => row.id;
  String get type => row.entityType;
  bool get pending => row.syncState != 'synced';

  String? s(String key) => data[key] as String?;
  String str(String key, [String fallback = '']) =>
      (data[key] as String?) ?? fallback;
  num? n(String key) => data[key] as num?;
  bool b(String key) => data[key] == true;
  List<String> list(String key) =>
      ((data[key] as List<dynamic>?) ?? const []).map((e) => '$e').toList();
  DateTime? dt(String key) {
    final v = data[key];
    return v is String ? DateTime.tryParse(v) : null;
  }
}

/// Local-first access to record-backed entities. Every write is one local transaction
/// with its outbox mutation; sync uploads it later.
class RecordsRepository {
  RecordsRepository(this._db, this._clock);
  final AppDatabase _db;
  final AppClock _clock;

  String newId() => newUuid7(now: _clock.now());
  DateTime get now => _clock.now();

  Stream<List<Rec>> watch(String ws, String type) => _db.recordDao
      .watchType(ws, type)
      .map((rows) => [for (final r in rows) Rec(r)]);

  Future<List<Rec>> all(String ws, String type) async => [
    for (final r in await _db.recordDao.ofType(ws, type)) Rec(r),
  ];

  Stream<Rec?> watchOne(String id) => _db.recordDao
      .watchById(id)
      .map((r) => r == null || r.deletedAt != null ? null : Rec(r));

  Future<String> create(
    String ws,
    String type,
    Map<String, Object?> data, {
    String? id,
  }) async {
    final rid = id ?? newId();
    await _db.recordDao.create(ws, type, rid, data, newId(), now);
    return rid;
  }

  Future<void> createAll(
    String ws,
    List<({String type, String id, Map<String, Object?> data})> rows,
  ) => _db.recordDao.createAll(ws, [
    for (final r in rows)
      (type: r.type, id: r.id, data: r.data, mutationId: newId()),
  ], now);

  Future<void> change(String id, Map<String, Object?> changes) =>
      _db.recordDao.change(id, changes, newId(), now);

  Future<void> remove(String id) => _db.recordDao.remove(id, newId(), now);
}

final recordsRepositoryProvider = Provider<RecordsRepository>(
  (ref) =>
      RecordsRepository(ref.watch(databaseProvider), ref.watch(clockProvider)),
);

/// Live list of one entity type in the signed-in workspace.
final recordsProvider = StreamProvider.autoDispose.family<List<Rec>, String>((
  ref,
  type,
) {
  final ws = ref.watch(authControllerProvider).value?.workspaceId;
  if (ws == null) return const Stream.empty();
  return ref.watch(recordsRepositoryProvider).watch(ws, type);
});

final recordProvider = StreamProvider.autoDispose.family<Rec?, String>(
  (ref, id) => ref.watch(recordsRepositoryProvider).watchOne(id),
);
