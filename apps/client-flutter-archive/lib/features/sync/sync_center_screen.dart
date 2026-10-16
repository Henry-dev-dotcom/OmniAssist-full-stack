import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../database/app_database.dart';
import 'sync_controller.dart';
import 'sync_status.dart';

final openConflictsProvider = StreamProvider.autoDispose<List<ConflictRecord>>(
  (ref) => ref.watch(databaseProvider).syncDao.watchOpenConflicts(),
);
final _rejectedProvider = StreamProvider.autoDispose<List<OutboxMutation>>(
  (ref) => ref.watch(databaseProvider).syncDao.watchRejected(),
);

const entityLabels = {
  'project': 'Project',
  'task': 'Task',
  'time_block': 'Time block',
  'milestone': 'Milestone',
  'review': 'Review',
  'review_item': 'Review item',
  'analysis_record': 'Analysis',
  'experiment_entry': 'Experiment',
};

/// A readable name for a conflict or upload: its title from the payload, if any.
String entityName(String type, String json) {
  final data = (jsonDecode(json) as Map<String, dynamic>?) ?? const {};
  final title = data['title'] ?? data['name'];
  return '${entityLabels[type] ?? type}${title == null ? '' : ': $title'}';
}

/// S22: state, pending count, last success, errors and conflicts, manual retry.
class SyncCenterScreen extends ConsumerWidget {
  const SyncCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncControllerProvider);
    final pending = ref.watch(pendingCountProvider).value ?? 0;
    final conflicts = ref.watch(openConflictsProvider).value ?? const [];
    final rejected = ref.watch(_rejectedProvider).value ?? const [];
    final summary = syncSummary(s, pending, conflicts.length);
    final l = MaterialLocalizations.of(context);
    final last = s.lastSyncAt?.toLocal();
    final dao = ref.read(databaseProvider).syncDao;
    return Scaffold(
      appBar: AppBar(title: const Text('Sync Center')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Icon(summary.icon),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    summary.text,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ],
          ),
          if (s.phase == SyncPhase.failed && s.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                s.error!.message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Changes waiting to upload'),
            trailing: Text('$pending'),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Last synced'),
            trailing: Text(
              last == null
                  ? 'Not yet'
                  : '${l.formatMediumDate(last)} '
                        '${l.formatTimeOfDay(TimeOfDay.fromDateTime(last))}',
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: s.phase == SyncPhase.syncing
                  ? null
                  : () => ref.read(syncControllerProvider.notifier).syncNow(),
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
          ),
          const Divider(height: 32),
          _Header('Conflicts (${conflicts.length})'),
          if (conflicts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('None. Edits from different devices merged cleanly.'),
            ),
          for (final c in conflicts)
            ListTile(
              leading: Icon(
                Icons.call_split,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(entityName(c.entityType, c.serverJson)),
              subtitle: const Text(
                'Changed here and on another device. Choose what to keep.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/app/sync/conflicts/${c.id}'),
            ),
          const Divider(height: 32),
          _Header('Uploads the server refused (${rejected.length})'),
          if (rejected.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('None.'),
            ),
          for (final m in rejected)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(entityName(m.entityType, m.payload)),
              subtitle: Text('${m.operation} · ${_reason(m.lastErrorCode)}'),
              trailing: Wrap(
                children: [
                  TextButton(
                    onPressed: () async {
                      await dao.retryRejected(m.mutationId);
                      ref.read(syncControllerProvider.notifier).syncNow();
                    },
                    child: const Text('Retry'),
                  ),
                  TextButton(
                    onPressed: () => dao.discardRejected(m.mutationId),
                    child: const Text('Discard'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _reason(String? code) => switch (code) {
    'VALIDATION_ERROR' => 'some values are not valid',
    'DOMAIN_RULE_VIOLATION' =>
      'it breaks a rule, for example a loop between milestones',
    'NOT_FOUND' => 'the record no longer exists',
    'FORBIDDEN' => 'it belongs to a workspace you cannot access',
    'IDEMPOTENCY_KEY_REUSED' => 'it was sent twice with different content',
    _ => code ?? 'refused',
  };
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    container: true,
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}
