import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../database/app_database.dart';
import '../../shared_widgets/async_state_view.dart';
import '../auth/auth_controller.dart';
import '../sync/sync_controller.dart';
import '../notifications/task_reminders_section.dart';
import 'tasks_repository.dart';

final _taskProvider = FutureProvider.autoDispose.family<Task?, String>(
  (ref, id) => ref.watch(databaseProvider).taskDao.byId(id),
);

final _projectsProvider = StreamProvider.autoDispose<List<Project>>((ref) {
  final ws = ref.watch(authControllerProvider).value?.workspaceId;
  return ws == null
      ? const Stream.empty()
      : ref.watch(projectsRepositoryProvider).watchActive(ws);
});

class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({required this.taskId, super.key});
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(_taskProvider(taskId));
    return Scaffold(
      appBar: AppBar(title: const Text('Task')),
      body: task.when(
        loading: () => const LoadingView(),
        error: (_, _) => const EmptyStateView(
          title: 'Cannot open this task',
          message: 'Go back and try again.',
        ),
        data: (t) => t == null || t.deletedAt != null
            ? const EmptyStateView(
                title: 'Task not found',
                message: 'It may have been deleted on another device.',
              )
            : _Form(task: t),
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.task});
  final Task task;
  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final _title = TextEditingController(text: widget.task.title);
  late final _desc = TextEditingController(text: widget.task.description ?? '');
  late String _status = widget.task.status;
  late String _priority = widget.task.priority;
  late DateTime? _due = widget.task.dueAt;
  late String? _project = widget.task.projectId;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due?.toLocal() ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _due = dueFromDate(picked));
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Enter a title.');
      return;
    }
    final changed = await ref
        .read(tasksRepositoryProvider)
        .edit(
          widget.task,
          TaskEdit(
            title: _title.text,
            description: _desc.text,
            status: _status,
            priority: _priority,
            dueAt: _due,
            projectId: _project,
          ),
        );
    if (changed) ref.read(syncControllerProvider.notifier).syncNow();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(_projectsProvider).value ?? const <Project>[];
    // A task can point at an archived project; keep it selectable so saving
    // does not silently unlink it.
    final known = projects.any((p) => p.id == _project);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _title,
          maxLength: 240,
          decoration: InputDecoration(labelText: 'Title', errorText: _error),
        ),
        TextField(
          controller: _desc,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Status'),
          items: [
            for (final s in taskStatuses)
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: (v) => setState(() => _status = v ?? _status),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _priority,
          decoration: const InputDecoration(labelText: 'Priority'),
          items: [
            for (final p in taskPriorities)
              DropdownMenuItem(value: p, child: Text(p)),
          ],
          onChanged: (v) => setState(() => _priority = v ?? _priority),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _project,
          decoration: const InputDecoration(labelText: 'Project'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('None')),
            for (final p in projects)
              DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
            if (_project != null && !known)
              DropdownMenuItem<String?>(
                value: _project,
                child: const Text('Archived project'),
              ),
          ],
          onChanged: (v) => setState(() => _project = v),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text(
            _due == null
                ? 'No due date'
                : 'Due ${_due!.toLocal().toString().split(' ').first}',
          ),
          onTap: _pickDate,
          trailing: _due == null
              ? null
              : IconButton(
                  tooltip: 'Clear due date',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _due = null),
                ),
        ),
        const SizedBox(height: 12),
        TaskRemindersSection(task: widget.task),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
