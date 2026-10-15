import 'package:drift/drift.dart';

/// One row per account and device: cursor and overall status.
class SyncState extends Table {
  TextColumn get deviceId => text()();
  TextColumn get accountId => text()();
  IntColumn get cursor => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('idle'))();

  @override
  Set<Column> get primaryKey => {deviceId};
}

/// Queue of local mutations awaiting upload. `mutationId` is the idempotency key.
class OutboxMutations extends Table {
  TextColumn get mutationId => text()();
  TextColumn get workspaceId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()(); // create | update | delete
  TextColumn get payload => text()(); // JSON of changed fields
  IntColumn get baseVersion => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {mutationId};
}

class ConflictRecords extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get baseJson => text().nullable()();
  TextColumn get localJson => text()();
  TextColumn get serverJson => text()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
