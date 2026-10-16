import 'package:drift/drift.dart';

import 'app_database.dart';

/// Explicit versioning. Add one `if (from < N)` block per schema bump, never edit old ones.
MigrationStrategy appMigrations(AppDatabase db) => MigrationStrategy(
  onCreate: (m) => m.createAll(),
  onUpgrade: (m, from, to) async {
    if (from < 2) {
      // Research entities move to the generic records table (decision 0003). The
      // tasks rebuild drops its foreign key to the old, never-used milestones table.
      await db.customStatement(
        'PRAGMA foreign_keys = OFF',
      ); // beforeOpen turns it on
      await m.alterTable(TableMigration(db.tasks, newColumns: [db.tasks.tags]));
      await m.deleteTable('milestones');
      await m.createTable(db.records);
      await m.createIndex(db.idxRecordsWorkspaceType);
    }
    // Task tags (decision 0005). Coming from v1, the rebuild above already added them.
    if (from == 2) await m.addColumn(db.tasks, db.tasks.tags);
  },
  beforeOpen: (details) async {
    await db.customStatement('PRAGMA foreign_keys = ON');
  },
);
