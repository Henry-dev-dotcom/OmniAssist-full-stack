import 'package:drift/drift.dart';

import 'app_database.dart';

/// Explicit versioning. Add one `if (from < N)` block per schema bump, never edit old ones.
MigrationStrategy appMigrations(AppDatabase db) => MigrationStrategy(
      onCreate: (m) => m.createAll(),
      onUpgrade: (m, from, to) async {
        // v1 is the first release. Future steps go here, for example:
        // if (from < 2) await m.addColumn(db.tasks, db.tasks.someColumn);
      },
      beforeOpen: (details) async {
        await db.customStatement('PRAGMA foreign_keys = ON');
      },
    );
