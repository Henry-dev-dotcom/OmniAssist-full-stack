import 'package:drift/drift.dart';

/// Columns every synchronized table carries. `syncState` is transfer metadata and is
/// separate from the domain `status` (Spec section 2: a task can be complete and pending_update).
mixin SyncedColumns on Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  IntColumn get version => integer().withDefault(const Constant(0))();
  TextColumn get syncState => text().withDefault(const Constant('synced'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Projects extends Table with SyncedColumns {
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get category => text()();
  TextColumn get status => text().withDefault(const Constant('planned'))();
  TextColumn get description => text().nullable()();
  IntColumn get progressValue => integer().withDefault(const Constant(0))();
}

class Tasks extends Table with SyncedColumns {
  TextColumn get projectId => text().nullable().references(Projects, #id)();
  TextColumn get milestoneId => text().nullable()(); // a Records row (v2)
  TextColumn get parentTaskId => text().nullable()();
  TextColumn get title => text().withLength(min: 1, max: 240)();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('inbox'))();
  TextColumn get priority => text().withDefault(const Constant('normal'))();
  DateTimeColumn get dueAt => dateTime().nullable()();
  IntColumn get estimatedMinutes => integer().nullable()();
  TextColumn get recurrenceRule => text().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
}

class TimeBlocks extends Table with SyncedColumns {
  TextColumn get taskId => text().nullable().references(Tasks, #id)();
  TextColumn get projectId => text().nullable().references(Projects, #id)();
  TextColumn get title => text().withLength(min: 1, max: 240)();
  TextColumn get category => text().withDefault(const Constant('focus'))();
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  TextColumn get status => text().withDefault(const Constant('planned'))();
}
