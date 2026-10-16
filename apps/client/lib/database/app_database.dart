import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'daos/project_dao.dart';
import 'daos/record_dao.dart';
import 'daos/reminder_dao.dart';
import 'daos/sync_dao.dart';
import 'daos/task_dao.dart';
import 'daos/time_block_dao.dart';
import 'migrations.dart';
import 'tables/core_tables.dart';
import 'tables/record_tables.dart';
import 'tables/reminder_tables.dart';
import 'tables/sync_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Projects,
    Records,
    Tasks,
    TimeBlocks,
    SyncState,
    OutboxMutations,
    ConflictRecords,
    Reminders,
    LocalSettings,
  ],
  daos: [TaskDao, ProjectDao, TimeBlockDao, ReminderDao, SyncDao, RecordDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Opens the on-disk database on mobile and desktop, and browser storage
  /// (OPFS or IndexedDB) on the web using the files in `web/`.
  factory AppDatabase.open() => AppDatabase(
    driftDatabase(
      name: 'omniassist',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    ),
  );

  static const currentSchemaVersion = 3;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => appMigrations(this);

  /// Removes every row on this device, children before parents so foreign keys hold.
  Future<void> wipe() => transaction(() async {
    for (final table in allTables.toList().reversed) {
      await delete(table).go();
    }
  });
}
