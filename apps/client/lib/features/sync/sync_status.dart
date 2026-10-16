import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import 'sync_controller.dart';

final pendingCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(databaseProvider).syncDao.watchPendingCount(),
);
final conflictCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(databaseProvider).syncDao.watchOpenConflictCount(),
);

/// One sync summary for the whole app (Spec 4.12 states). Icon, text and color together.
({IconData icon, String text, bool attention}) syncSummary(
  SyncUiState sync,
  int pending,
  int conflicts,
) {
  if (conflicts > 0) {
    return (
      icon: Icons.call_split,
      text: conflicts == 1
          ? '1 conflict to resolve'
          : '$conflicts conflicts to resolve',
      attention: true,
    );
  }
  if (sync.phase == SyncPhase.syncing) {
    return (icon: Icons.sync, text: 'Syncing', attention: false);
  }
  final waiting = pending == 1
      ? '1 change waiting to sync'
      : '$pending changes waiting to sync';
  if (sync.phase == SyncPhase.failed) {
    return (
      icon: Icons.cloud_off,
      text: pending > 0 ? waiting : 'Saved on this device',
      attention: true,
    );
  }
  if (pending > 0) {
    return (icon: Icons.cloud_upload_outlined, text: waiting, attention: false);
  }
  return (
    icon: Icons.cloud_done_outlined,
    text: sync.lastSyncAt == null ? 'Saved on this device' : 'Synced',
    attention: false,
  );
}

/// Compact, tappable status; opens the Sync Center (or the conflicts in it).
class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = syncSummary(
      ref.watch(syncControllerProvider),
      ref.watch(pendingCountProvider).value ?? 0,
      ref.watch(conflictCountProvider).value ?? 0,
    );
    final color = s.attention ? Theme.of(context).colorScheme.error : null;
    void open() => context.push('/app/sync');
    // On phones the words do not fit beside the title (large text especially).
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Semantics(
      button: true,
      label: 'Sync status: ${s.text}. Open Sync Center',
      excludeSemantics: true,
      child: compact
          ? IconButton(
              tooltip: s.text,
              onPressed: open,
              icon: Icon(s.icon, color: color),
            )
          : TextButton.icon(
              onPressed: open,
              icon: Icon(s.icon, size: 18, color: color),
              label: Text(s.text, style: TextStyle(color: color)),
            ),
    );
  }
}

/// Shown above every screen only when something needs attention or is waiting.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final pending = ref.watch(pendingCountProvider).value ?? 0;
    final conflicts = ref.watch(conflictCountProvider).value ?? 0;
    final s = syncSummary(sync, pending, conflicts);
    if (!s.attention && pending == 0) return const SizedBox.shrink();
    return Material(
      color: s.attention
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => context.push('/app/sync'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(s.icon, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(s.text)),
              const Text('Sync Center'),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
