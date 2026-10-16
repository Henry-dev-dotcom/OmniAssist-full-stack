import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/ids/entity_ids.dart';
import '../../core/time/app_clock.dart';
import '../../database/app_database.dart';

const projectCategories = [
  'personal',
  'thesis',
  'grant',
  'review',
  'experiment',
  'analysis',
  'software',
];

/// Local-first: screens read and write the local database only. The sync engine
/// uploads the outbox and merges server changes in.
class ProjectsRepository {
  ProjectsRepository(this._db, this._clock);
  final AppDatabase _db;
  final AppClock _clock;

  Stream<List<Project>> watchActive(String ws) =>
      _db.projectDao.watchActive(ws);
  Stream<List<Project>> watchArchived(String ws) =>
      _db.projectDao.watchArchived(ws);

  Future<void> create(String ws, String name, String category) =>
      _db.projectDao.createWithOutbox(
        id: newUuid7(now: _clock.now()),
        workspaceId: ws,
        name: name.trim(),
        category: category,
        mutationId: newUuid7(now: _clock.now()),
        now: _clock.now(),
      );

  Stream<Project?> watchOne(String id) => _db.projectDao.watchById(id);

  Future<void> setArchived(String id, bool archived) =>
      update(id, {'status': archived ? 'archived' : 'planned'});

  Future<void> update(String id, Map<String, Object?> changes) =>
      _db.projectDao.updateWithOutbox(
        id: id,
        changes: changes,
        mutationId: newUuid7(now: _clock.now()),
        now: _clock.now(),
      );

  /// Deletes only an empty project; otherwise returns why not (decision 0003).
  Future<String?> delete(String id) async {
    final linkedTasks = await (_db.select(
      _db.tasks,
    )..where((t) => t.projectId.equals(id) & t.deletedAt.isNull())).get();
    final linkedRecords =
        (await (_db.select(
          _db.records,
        )..where((r) => r.deletedAt.isNull())).get()).where(
          (r) =>
              (jsonDecode(r.data) as Map<String, dynamic>)['project_id'] == id,
        );
    if (linkedTasks.isNotEmpty || linkedRecords.isNotEmpty) {
      return 'This project still has work in it. Archive it, or move or delete its '
          'tasks, milestones, reviews, analyses and experiments first.';
    }
    await _db.projectDao.deleteWithOutbox(
      id: id,
      mutationId: newUuid7(now: _clock.now()),
      now: _clock.now(),
    );
    return null;
  }
}
