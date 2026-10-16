import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/ids/entity_ids.dart';
import '../../database/app_database.dart';
import '../../shared_widgets/async_state_view.dart';
import 'sync_center_screen.dart';
import 'sync_controller.dart';

enum Choice { mine, server, both }

/// What to keep per field: (values to upload, values to take from the server).
/// "Both" joins two texts so neither version is lost.
({Map<String, Object?> local, Map<String, Object?> server}) planResolution(
  Map<String, dynamic> mine,
  Map<String, dynamic> theirs,
  Map<String, Choice> choices,
) {
  final local = <String, Object?>{}, server = <String, Object?>{};
  for (final key in mine.keys) {
    switch (choices[key] ?? Choice.mine) {
      case Choice.mine:
        local[key] = mine[key];
      case Choice.server:
        server[key] = theirs[key];
      case Choice.both:
        local[key] =
            '${theirs[key] ?? ''}\n\n--- other version ---\n${mine[key] ?? ''}';
    }
  }
  return (local: local, server: server);
}

/// S23: compare this device's edit with the server's and choose per field.
class ConflictPage extends ConsumerWidget {
  const ConflictPage({required this.conflictId, super.key});
  final String conflictId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(openConflictsProvider);
    return all.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (_, _) => const Scaffold(
        body: EmptyStateView(
          title: 'Cannot load conflict',
          message: 'Restart the app. Your data is safe.',
        ),
      ),
      data: (rows) {
        final c = rows.where((r) => r.id == conflictId).firstOrNull;
        return c == null
            ? Scaffold(
                appBar: AppBar(),
                body: const EmptyStateView(
                  title: 'Already resolved',
                  message: 'This conflict has been settled.',
                ),
              )
            : _Resolver(conflict: c);
      },
    );
  }
}

class _Resolver extends ConsumerStatefulWidget {
  const _Resolver({required this.conflict});
  final ConflictRecord conflict;
  @override
  ConsumerState<_Resolver> createState() => _ResolverState();
}

class _ResolverState extends ConsumerState<_Resolver> {
  late final Map<String, dynamic> _mine =
      jsonDecode(widget.conflict.localJson) as Map<String, dynamic>;
  late final Map<String, dynamic> _theirs =
      jsonDecode(widget.conflict.serverJson) as Map<String, dynamic>;
  late final Map<String, Choice> _choices = {
    for (final k in _mine.keys) k: Choice.mine,
  };

  Future<void> _resolve(String label) async {
    final plan = planResolution(_mine, _theirs, _choices);
    final clock = ref.read(clockProvider);
    await ref
        .read(databaseProvider)
        .syncDao
        .resolveConflict(
          conflict: widget.conflict,
          local: plan.local,
          server: plan.server,
          serverVersion: (_theirs['version'] as num?)?.toInt() ?? 0,
          mutationId: newUuid7(now: clock.now()),
          now: clock.now(),
        );
    // Closing the server's record is best effort; the new mutation carries the choice.
    unawaited(
      ref
          .read(apiClientProvider)
          .post('/sync/conflicts/${widget.conflict.id}/resolve', {
            'resolution': label,
          })
          .catchError((Object _) => null),
    );
    ref.read(syncControllerProvider.notifier).syncNow();
    if (mounted) context.pop();
  }

  String _show(Object? v) => v == null || '$v'.isEmpty
      ? '(empty)'
      : v is List || v is Map
      ? jsonEncode(v)
      : '$v';

  @override
  Widget build(BuildContext context) {
    final c = widget.conflict;
    final allMine = _choices.values.every((x) => x == Choice.mine);
    final allServer = _choices.values.every((x) => x == Choice.server);
    return Scaffold(
      appBar: AppBar(title: const Text('Resolve conflict')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            entityName(c.entityType, c.serverJson),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'This was changed on this device and on another one. Pick what to keep '
            'for each field. Nothing is lost until you save.',
          ),
          const SizedBox(height: 16),
          for (final key in _mine.keys) ...[
            Text(
              key.replaceAll('_', ' '),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            RadioGroup<Choice>(
              groupValue: _choices[key],
              onChanged: (v) =>
                  setState(() => _choices[key] = v ?? Choice.mine),
              child: Column(
                children: [
                  RadioListTile<Choice>(
                    value: Choice.mine,
                    title: const Text('This device'),
                    subtitle: SelectableText(_show(_mine[key])),
                  ),
                  RadioListTile<Choice>(
                    value: Choice.server,
                    title: const Text('Other device (server)'),
                    subtitle: SelectableText(_show(_theirs[key])),
                  ),
                  if (_mine[key] is String || _theirs[key] is String)
                    const RadioListTile<Choice>(
                      value: Choice.both,
                      title: Text('Keep both texts'),
                    ),
                ],
              ),
            ),
            const Divider(),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _resolve(
                  allMine
                      ? 'keep_local'
                      : (allServer ? 'keep_server' : 'merge'),
                ),
                child: const Text('Save choices'),
              ),
              OutlinedButton(
                onPressed: () =>
                    setState(() => _choices.updateAll((_, _) => Choice.mine)),
                child: const Text('Choose all mine'),
              ),
              OutlinedButton(
                onPressed: () =>
                    setState(() => _choices.updateAll((_, _) => Choice.server)),
                child: const Text('Choose all server'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
