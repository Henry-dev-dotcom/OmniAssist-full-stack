import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../database/app_database.dart';
import '../auth/auth_controller.dart';
import '../sync/sync_controller.dart';

/// Floating "+" shown on every primary screen (Spec 4.3: capture from anywhere).
class QuickCaptureButton extends ConsumerWidget {
  const QuickCaptureButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => FloatingActionButton(
        tooltip: 'Quick capture',
        onPressed: () async {
          final ws = ref.read(authControllerProvider).value?.workspaceId;
          if (ws == null) return;
          final title = await showDialog<String>(
              context: context, builder: (_) => const _CaptureDialog());
          if (title == null) return;
          await ref.read(tasksRepositoryProvider).capture(ws, title);
          ref.read(syncControllerProvider.notifier).syncNow();
        },
        child: const Icon(Icons.add),
      );
}

class _CaptureDialog extends StatefulWidget {
  const _CaptureDialog();
  @override
  State<_CaptureDialog> createState() => _CaptureDialogState();
}

class _CaptureDialogState extends State<_CaptureDialog> {
  final _title = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Enter a title.');
      return;
    }
    Navigator.pop(context, _title.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Quick capture'),
        content: TextField(
          controller: _title,
          autofocus: true,
          maxLength: 240,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(labelText: 'What needs doing?', errorText: _error),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Add to Inbox')),
        ],
      );
}

/// One task row with a completion checkbox.
class TaskTile extends ConsumerWidget {
  const TaskTile({required this.task, this.trailing, super.key});
  final Task task;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = task.status == 'complete';
    return ListTile(
      leading: Checkbox(
        value: done,
        semanticLabel: done ? 'Mark ${task.title} not done' : 'Mark ${task.title} done',
        onChanged: (v) async {
          await ref.read(tasksRepositoryProvider).setDone(task.id, v ?? false);
          ref.read(syncControllerProvider.notifier).syncNow();
        },
      ),
      title: Text(task.title,
          style: done
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null),
      onTap: () => context.push('/app/tasks/${task.id}'),
      subtitle: task.syncState == 'synced' ? null : const Text('Waiting to sync'),
      trailing: trailing,
    );
  }
}
