import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../database/app_database.dart';
import '../../shared_widgets/async_state_view.dart';
import '../auth/auth_controller.dart';
import '../sync/sync_controller.dart';
import '../tasks/task_widgets.dart';
import 'projects_repository.dart';

final _projectsProvider = StreamProvider.autoDispose
    .family<List<Project>, bool>((ref, archived) {
      final ws = ref.watch(authControllerProvider).value?.workspaceId;
      if (ws == null) return const Stream.empty();
      final repo = ref.watch(projectsRepositoryProvider);
      return archived ? repo.watchArchived(ws) : repo.watchActive(ws);
    });

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});
  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  bool _archived = false;

  Future<void> _pull() => ref.read(syncControllerProvider.notifier).syncNow();

  Future<void> _add() async {
    final ws = ref.read(authControllerProvider).value?.workspaceId;
    if (ws == null) return;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _NewProjectDialog(),
    );
    if (result == null) return;
    await ref.read(projectsRepositoryProvider).create(ws, result.$1, result.$2);
    unawaited(ref.read(syncControllerProvider.notifier).syncNow());
  }

  @override
  Widget build(BuildContext context) {
    final archived = _archived;
    final projects = ref.watch(_projectsProvider(archived));
    return Scaffold(
      appBar: AppBar(
        title: Text(archived ? 'Archived projects' : 'Projects'),
        actions: [
          if (!archived)
            IconButton(
              tooltip: 'New project',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: _add,
            ),
          IconButton(
            tooltip: archived ? 'Show active' : 'Show archived',
            icon: Icon(archived ? Icons.folder_open : Icons.archive_outlined),
            onPressed: () => setState(() => _archived = !archived),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _pull,
          ),
        ],
      ),
      floatingActionButton: const QuickCaptureButton(),
      body: Column(
        children: [
          if (ref.watch(syncControllerProvider).phase == SyncPhase.failed)
            MaterialBanner(
              content: Text(
                '${ref.watch(syncControllerProvider).error?.message ?? 'Sync failed.'} '
                'Showing saved data.',
              ),
              actions: [
                TextButton(onPressed: _pull, child: const Text('Retry')),
              ],
            ),
          Expanded(
            child: projects.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const EmptyStateView(
                title: 'Cannot load projects',
                message: 'Restart the app. Your data is safe.',
              ),
              data: (rows) => rows.isEmpty
                  ? EmptyStateView(
                      title: archived
                          ? 'No archived projects'
                          : 'No projects yet',
                      message: archived
                          ? 'Archived projects appear here.'
                          : 'Tap + to add your first project.',
                    )
                  : ListView(
                      children: [
                        for (final p in rows)
                          ListTile(
                            title: Text(p.name),
                            onTap: () => context.push('/app/projects/${p.id}'),
                            subtitle: Text(
                              '${p.category} · ${p.progressValue}%'
                              '${p.syncState == 'synced' ? '' : ' · waiting to sync'}',
                            ),
                            trailing: IconButton(
                              tooltip: archived ? 'Restore' : 'Archive',
                              icon: Icon(
                                archived
                                    ? Icons.unarchive_outlined
                                    : Icons.archive_outlined,
                              ),
                              onPressed: () async {
                                await ref
                                    .read(projectsRepositoryProvider)
                                    .setArchived(p.id, !archived);
                                unawaited(
                                  ref
                                      .read(syncControllerProvider.notifier)
                                      .syncNow(),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();
  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final _name = TextEditingController();
  String _category = 'personal';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New project'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: 120,
          decoration: InputDecoration(labelText: 'Name', errorText: _error),
        ),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [
            for (final c in projectCategories)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_name.text.trim().isEmpty) {
            setState(() => _error = 'Enter a name.');
            return;
          }
          Navigator.pop(context, (_name.text, _category));
        },
        child: const Text('Create'),
      ),
    ],
  );
}
