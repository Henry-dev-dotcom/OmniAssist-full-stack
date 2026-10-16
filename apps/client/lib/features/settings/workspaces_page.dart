import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors/app_error.dart';
import '../../shared_widgets/async_state_view.dart';
import '../auth/auth_controller.dart';
import '../milestones/milestones_tab.dart';
import '../sync/sync_controller.dart';

final _workspacesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) async => [
        for (final w
            in await ref.read(apiClientProvider).get('/workspaces')
                as List<dynamic>)
          w as Map<String, dynamic>,
      ],
    );

/// S04: switch between workspaces and manage them (Spec 4.2).
class WorkspacesPage extends ConsumerWidget {
  const WorkspacesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(authControllerProvider).value?.workspaceId;
    final list = ref.watch(_workspacesProvider);
    final api = ref.read(apiClientProvider);

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } on AppError catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
      ref.invalidate(_workspacesProvider);
    }

    Future<void> create() async {
      final name = await askTitle(context, 'New workspace');
      if (name == null) return;
      await run(() async {
        final ws = await api.post('/workspaces', {
          'name': name,
        }) as Map<String, dynamic>;
        await ref
            .read(authControllerProvider.notifier)
            .switchWorkspace(ws['id'] as String);
        ref.read(syncControllerProvider.notifier).syncNow();
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Workspaces')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: create,
        icon: const Icon(Icons.add),
        label: const Text('Workspace'),
      ),
      body: list.when(
        loading: () => const LoadingView(),
        error: (e, _) => EmptyStateView(
          title: 'Needs a connection',
          message: e is AppError
              ? '${e.message} Your current workspace keeps working offline.'
              : 'Workspaces are managed online. Your current workspace keeps working offline.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(_workspacesProvider),
        ),
        data: (rows) => ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Each workspace keeps its own projects, tasks and research separate. '
                'Tap one to switch.',
              ),
            ),
            for (final w in rows)
              _WorkspaceTile(
                ws: w,
                current: w['id'] == current,
                canDelete: rows.length > 1 && w['id'] != current,
                onSwitch: () => run(() async {
                  await ref
                      .read(authControllerProvider.notifier)
                      .switchWorkspace(w['id'] as String);
                  if (context.mounted) Navigator.of(context).maybePop();
                }),
                onRename: () async {
                  final name = await askTitle(context, 'Rename ${w['name']}');
                  if (name == null) return;
                  await run(
                    () => api.patch('/workspaces/${w['id']}', {'name': name}),
                  );
                },
                onArchive: () => run(
                  () => api.patch('/workspaces/${w['id']}', {
                    'archived': w['archived_at'] == null,
                  }),
                ),
                onDelete: () async {
                  final typed = await showDialog<String>(
                    context: context,
                    builder: (_) => _DeleteDialog(name: w['name'] as String),
                  );
                  if (typed == null) return;
                  await run(
                    () => api.delete(
                      '/workspaces/${w['id']}',
                      body: {'confirm_name': typed},
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

enum _Action { rename, archive, delete }

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
    required this.ws,
    required this.current,
    required this.canDelete,
    required this.onSwitch,
    required this.onRename,
    required this.onArchive,
    required this.onDelete,
  });
  final Map<String, dynamic> ws;
  final bool current;
  final bool canDelete;
  final VoidCallback onSwitch;
  final VoidCallback onRename;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final archived = ws['archived_at'] != null;
    return ListTile(
      leading: Icon(
        current ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      ),
      title: Text('${ws['name']}'),
      subtitle: Text(
        [if (current) 'Open now', if (archived) 'Archived'].join(' · '),
      ),
      selected: current,
      onTap: current ? null : onSwitch,
      trailing: PopupMenuButton<_Action>(
        tooltip: 'Actions for ${ws['name']}',
        onSelected: (a) => switch (a) {
          _Action.rename => onRename(),
          _Action.archive => onArchive(),
          _Action.delete => onDelete(),
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: _Action.rename, child: Text('Rename')),
          PopupMenuItem(
            value: _Action.archive,
            child: Text(archived ? 'Restore' : 'Archive'),
          ),
          if (canDelete)
            const PopupMenuItem(value: _Action.delete, child: Text('Delete…')),
        ],
      ),
    );
  }
}

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.name});
  final String name;
  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Delete ${widget.name}?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'This permanently deletes every project, task, review, analysis and '
          'experiment in it, on every device. Export it first if you want a copy.',
        ),
        TextField(
          controller: _c,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Type "${widget.name}" to confirm',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        ),
        onPressed: _c.text.trim() == widget.name
            ? () => Navigator.pop(context, _c.text.trim())
            : null,
        child: const Text('Delete'),
      ),
    ],
  );
}
