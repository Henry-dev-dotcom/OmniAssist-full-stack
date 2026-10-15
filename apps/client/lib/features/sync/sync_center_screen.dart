import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'sync_controller.dart';

final _pendingProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(databaseProvider).syncDao.watchPendingCount(),
);
final _conflictsProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(databaseProvider).syncDao.watchOpenConflictCount(),
);

class SyncCenterScreen extends ConsumerWidget {
  const SyncCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncControllerProvider);
    final pending = ref.watch(_pendingProvider).value ?? 0;
    final conflicts = ref.watch(_conflictsProvider).value ?? 0;
    final headline = switch (s.phase) {
      SyncPhase.syncing => 'Syncing...',
      SyncPhase.failed => s.error?.message ?? 'Sync failed.',
      SyncPhase.idle =>
        pending == 0 ? 'Everything is synced.' : 'Waiting to sync.',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Sync Center')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(headline, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Changes waiting to upload'),
            trailing: Text('$pending'),
          ),
          ListTile(
            leading: const Icon(Icons.warning_amber_outlined),
            title: const Text('Conflicts to review'),
            trailing: Text('$conflicts'),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Last synced'),
            trailing: Text(
              s.lastSyncAt?.toLocal().toString().split('.').first ?? 'Not yet',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: s.phase == SyncPhase.syncing
                ? null
                : () => ref.read(syncControllerProvider.notifier).syncNow(),
            icon: const Icon(Icons.sync),
            label: const Text('Sync now'),
          ),
        ],
      ),
    );
  }
}
