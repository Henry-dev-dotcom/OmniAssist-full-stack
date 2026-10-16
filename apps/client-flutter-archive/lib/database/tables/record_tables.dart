import 'package:drift/drift.dart';

import 'core_tables.dart';

/// Milestones, reviews, review items, analyses, experiments, revisions and activity
/// (decision 0003). `data` is the entity as JSON with API field names, so pulled payloads
/// merge per field and pushes send the same shape back.
@DataClassName('RecordRow')
@TableIndex(
  name: 'idx_records_workspace_type',
  columns: {#workspaceId, #entityType},
)
class Records extends Table with SyncedColumns {
  TextColumn get entityType => text()();
  TextColumn get data => text()();
}
