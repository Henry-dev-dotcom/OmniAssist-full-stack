import 'package:drift/drift.dart';

/// Reminders live on the device so they fire offline. Status values match the server:
/// scheduled, sent, dismissed, snoozed, failed, acted_on, cancelled.
class Reminders extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get taskId => text()();
  TextColumn get title => text()();
  TextColumn get offsetSpec => text()();
  TextColumn get urgency => text().withDefault(const Constant('normal'))();
  DateTimeColumn get remindAt => dateTime()();
  TextColumn get status => text().withDefault(const Constant('scheduled'))();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  DateTimeColumn get sentAt => dateTime().nullable()();
  DateTimeColumn get readAt => dateTime().nullable()();
  TextColumn get failureReason => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Small key/value store for device settings such as quiet hours.
class LocalSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
