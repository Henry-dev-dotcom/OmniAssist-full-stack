import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/database/app_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('schema version is explicit', () {
    expect(db.schemaVersion, AppDatabase.currentSchemaVersion);
  });

  test('core and sync tables exist', () async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = rows.map((r) => r.read<String>('name')).toSet();
    expect(
      names,
      containsAll({
        'projects',
        'records',
        'tasks',
        'time_blocks',
        'sync_state',
        'outbox_mutations',
        'conflict_records',
      }),
    );
  });

  test('foreign keys are enforced', () async {
    final r = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(r.read<int>('foreign_keys'), 1);
  });
}
