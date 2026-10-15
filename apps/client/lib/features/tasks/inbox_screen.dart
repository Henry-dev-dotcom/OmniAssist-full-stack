import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../database/app_database.dart';
import '../../shared_widgets/async_state_view.dart';
import '../auth/auth_controller.dart';
import '../sync/sync_controller.dart';
import 'task_widgets.dart';

final _inboxProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  final ws = ref.watch(authControllerProvider).value?.workspaceId;
  return ws == null
      ? const Stream.empty()
      : ref.watch(tasksRepositoryProvider).watchInbox(ws);
});

final _activeProjectsProvider = StreamProvider.autoDispose<List<Project>>((
  ref,
) {
  final ws = ref.watch(authControllerProvider).value?.workspaceId;
  return ws == null
      ? const Stream.empty()
      : ref.watch(projectsRepositoryProvider).watchActive(ws);
});

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  Future<void> _move(BuildContext context, WidgetRef ref, Task t) async {
    final projects = ref.read(_activeProjectsProvider).value ?? const [];
    if (projects.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Create a project first.')));
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Move to project'),
        children: [
          for (final p in projects)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, p.id),
              child: Text(p.name),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await ref.read(tasksRepositoryProvider).moveToProject(t.id, picked);
    ref.read(syncControllerProvider.notifier).syncNow();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(_inboxProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Inbox')),
      floatingActionButton: const QuickCaptureButton(),
      body: inbox.when(
        loading: () => const LoadingView(),
        error: (_, _) => const EmptyStateView(
          title: 'Cannot load the Inbox',
          message: 'Restart the app. Your data is safe.',
        ),
        data: (rows) => rows.isEmpty
            ? const EmptyStateView(
                title: 'Inbox is empty',
                message: 'Tap + to capture a task. Sort it later.',
              )
            : ListView(
                children: [
                  for (final t in rows)
                    TaskTile(
                      task: t,
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Sort ${t.title}',
                        onSelected: (v) async {
                          if (v == 'move') {
                            await _move(context, ref, t);
                          } else {
                            await ref
                                .read(tasksRepositoryProvider)
                                .archive(t.id);
                            ref.read(syncControllerProvider.notifier).syncNow();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'move',
                            child: Text('Move to project'),
                          ),
                          PopupMenuItem(
                            value: 'archive',
                            child: Text('Archive'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
