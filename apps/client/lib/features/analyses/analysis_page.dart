import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../shared_widgets/async_state_view.dart';
import '../activity/activity_view.dart';
import '../auth/auth_controller.dart';
import '../milestones/milestones_tab.dart';
import '../records/records_repository.dart';
import '../sync/sync_controller.dart';
import 'analyses_tab.dart';

/// S17: one analysis record, its run result and next action.
class AnalysisPage extends ConsumerWidget {
  const AnalysisPage({required this.analysisId, super.key});
  final String analysisId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(recordProvider(analysisId))
      .when(
        loading: () => const Scaffold(body: LoadingView()),
        error: (_, _) => const Scaffold(
          body: EmptyStateView(
            title: 'Cannot load analysis',
            message: 'Restart the app. Your data is safe.',
          ),
        ),
        data: (a) => a == null
            ? Scaffold(
                appBar: AppBar(),
                body: const EmptyStateView(
                  title: 'Analysis not found',
                  message: 'It may have been deleted on another device.',
                ),
              )
            : _AnalysisEditor(key: ValueKey(a.id), a: a),
      );
}

const _text = <(String, String, int)>[
  ('title', 'Title', 240),
  ('purpose', 'Purpose', 5000),
  ('repository_url', 'Repository URL', 2000),
  ('branch_name', 'Branch', 255),
  ('commit_ref', 'Commit', 100),
  ('data_source_ref', 'Data source', 2000),
  ('environment', 'Environment (versions, packages)', 5000),
  ('result_summary', 'Result', 20000),
  ('error_details', 'Error', 20000),
  ('next_action', 'Next action', 2000),
];

class _AnalysisEditor extends ConsumerStatefulWidget {
  const _AnalysisEditor({required this.a, super.key});
  final Rec a;
  @override
  ConsumerState<_AnalysisEditor> createState() => _AnalysisEditorState();
}

class _AnalysisEditorState extends ConsumerState<_AnalysisEditor> {
  late final _c = {
    for (final (k, _, _) in _text)
      k: TextEditingController(text: widget.a.str(k)),
  };
  late String _status = widget.a.str('status', 'planned');
  late String? _language = widget.a.s('language');
  late String? _milestone = widget.a.s('milestone_id');
  String? _error;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _val(String k) =>
      _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim();

  Future<void> _save() async {
    final a = widget.a;
    if (_val('title') == null) {
      setState(() => _error = 'Enter a title.');
      return;
    }
    final url = _val('repository_url');
    final uri = url == null ? null : Uri.tryParse(url);
    if (url != null &&
        (uri == null ||
            !{'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty)) {
      setState(
        () =>
            _error = 'The repository URL must start with http:// or https://.',
      );
      return;
    }
    final changes = <String, Object?>{
      for (final (k, _, _) in _text)
        if (_val(k) != a.s(k)) k: _val(k),
      if (_status != a.s('status')) 'status': _status,
      if (_language != a.s('language')) 'language': _language,
      if (_milestone != a.s('milestone_id')) 'milestone_id': _milestone,
    };
    if (changes.isNotEmpty) {
      await ref.read(recordsRepositoryProvider).change(a.id, changes);
      ref.read(syncControllerProvider.notifier).syncNow();
    }
    if (mounted) {
      setState(() => _error = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved on this device')));
    }
  }

  Future<void> _taskFromNextAction() async {
    final ws = ref.read(authControllerProvider).value?.workspaceId;
    final next = _val('next_action');
    if (ws == null || next == null) return;
    await ref
        .read(tasksRepositoryProvider)
        .createIn(
          ws,
          title: next.length > 240 ? next.substring(0, 240) : next,
          projectId: widget.a.str('project_id'),
          milestoneId: _milestone,
        );
    ref.read(syncControllerProvider.notifier).syncNow();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task created in this project')),
      );
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this analysis record?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(recordsRepositoryProvider).remove(widget.a.id);
    ref.read(syncControllerProvider.notifier).syncNow();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.a.str('status', 'planned');
    final allowed = {saved, ...analysisTransitions[saved] ?? const <String>{}};
    final milestones = projectMilestones(
      ref.watch(recordsProvider('milestone')).value ?? const [],
      widget.a.str('project_id'),
    );
    final lastRun = widget.a.dt('last_run_at');
    final l = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.a.str('title')),
        actions: [
          IconButton(
            tooltip: 'Delete analysis',
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
          ),
          FilledButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    for (final s in analysisStatuses)
                      if (allowed.contains(s))
                        DropdownMenuItem(
                          value: s,
                          child: Row(
                            children: [
                              Icon(analysisIcon(s), size: 18),
                              const SizedBox(width: 8),
                              Text(s),
                            ],
                          ),
                        ),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? _status),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _language,
                  decoration: const InputDecoration(labelText: 'Language'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Not set')),
                    DropdownMenuItem(value: 'r', child: Text('R')),
                    DropdownMenuItem(value: 'python', child: Text('Python')),
                  ],
                  onChanged: (v) => setState(() => _language = v),
                ),
              ),
            ],
          ),
          if (lastRun != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Last run ${l.formatMediumDate(lastRun.toLocal())} '
                '${l.formatTimeOfDay(TimeOfDay.fromDateTime(lastRun.toLocal()))}',
              ),
            ),
          DropdownButtonFormField<String?>(
            initialValue: milestones.any((m) => m.id == _milestone)
                ? _milestone
                : null,
            decoration: const InputDecoration(labelText: 'Milestone'),
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              for (final m in milestones)
                DropdownMenuItem(value: m.id, child: Text(m.str('title'))),
            ],
            onChanged: (v) => setState(() => _milestone = v),
          ),
          for (final (k, label, max) in _text)
            TextField(
              controller: _c[k],
              maxLength: max > 2000 ? null : max,
              minLines: 1,
              maxLines: max > 2000 ? 8 : 2,
              decoration: InputDecoration(labelText: label),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _taskFromNextAction,
              icon: const Icon(Icons.add_task),
              label: const Text('Create task from next action'),
            ),
          ),
          const Divider(height: 32),
          Semantics(
            header: true,
            container: true,
            child: Text(
              'History',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ActivityList(
            entityIds: {widget.a.id},
            names: {widget.a.id: widget.a.str('title')},
            shrinkWrap: true,
          ),
        ],
      ),
    );
  }
}
