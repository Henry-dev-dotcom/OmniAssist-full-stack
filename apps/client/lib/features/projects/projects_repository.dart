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

  Future<void> setArchived(String id, bool archived) =>
      _db.projectDao.updateStatusWithOutbox(
        id: id,
        status: archived ? 'archived' : 'planned',
        mutationId: newUuid7(now: _clock.now()),
        now: _clock.now(),
      );
}
