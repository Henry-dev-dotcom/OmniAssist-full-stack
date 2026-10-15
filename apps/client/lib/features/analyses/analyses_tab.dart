import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../milestones/milestones_tab.dart';
import '../records/records_repository.dart';
import '../sync/sync_controller.dart';

const analysisStatuses = [
  'planned',
  'running',
  'succeeded',
  'failed',
  'blocked',
  'archived',
];

/// Same moves the server allows (decision 0003).
const analysisTransitions = <String, Set<String>>{
  'planned': {'running', 'succeeded', 'failed', 'blocked', 'archived'},
  'running': {'succeeded', 'failed', 'blocked', 'planned'},
  'succeeded': {'running', 'planned', 'archived'},
  'failed': {'running', 'planned', 'blocked', 'archived'},
  'blocked': {'planned', 'running', 'archived'},
  'archived': {'planned'},
};

IconData analysisIcon(String? status) => switch (status) {
  'running' => Icons.play_circle_outline,
  'succeeded' => Icons.check_circle_outline,
  'failed' => Icons.error_outline,
  'blocked' => Icons.block,
  'archived' => Icons.archive_outlined,
  _ => Icons.radio_button_unchecked,
};

/// S16: analysis ledger for one project. OmniAssist records runs; it never executes code.
class AnalysesTab extends ConsumerStatefulWidget {
  const AnalysesTab({required this.projectId, super.key});
  final String projectId;
  @override
  ConsumerState<AnalysesTab> createState() => _AnalysesTabState();
}

class _AnalysesTabState extends ConsumerState<AnalysesTab> {
  String? _status; // null = all but archived

  Future<void> _add() async {
    final ws = ref.read(authControllerProvider).value?.workspaceId;
    final title = await askTitle(context, 'New analysis record');
    if (ws == null || title == null) return;
    final id = await ref.read(recordsRepositoryProvider).create(
      ws,
      'analysis_record',
      {'project_id': widget.projectId, 'title': title, 'status': 'planned'},
    );
    ref.read(syncControllerProvider.notifier).syncNow();
    if (mounted) await context.push('/app/analyses/$id');
  }

  @override
  Widget build(BuildContext context) {
    final all = [
      for (final a
          in ref.watch(recordsProvider('analysis_record')).value ??
              const <Rec>[])
        if (a.s('project_id') == widget.projectId) a,
    ];
    final shown = [
      for (final a in all)
        if (_status == null
            ? a.s('status') != 'archived'
            : a.s('status') == _status)
          a,
    ]..sort((a, b) => b.row.updatedAt.compareTo(a.row.updatedAt));
    final error = Theme.of(context).colorScheme.error;
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Track what ran, what failed and what to do next. '
                  'OmniAssist never runs your code.',
                ),
              ),
              FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: const Text('Analysis'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final s in [null, ...analysisStatuses])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      s == null
                          ? 'Active (${all.where((a) => a.s('status') != 'archived').length})'
                          : '$s (${all.where((a) => a.s('status') == s).length})',
                    ),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
                ),
            ],
          ),
        ),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No analysis records here.'),
          ),
        for (final a in shown)
          ListTile(
            leading: Icon(
              analysisIcon(a.s('status')),
              color: a.s('status') == 'failed' ? error : null,
            ),
            title: Text(a.str('title')),
            subtitle: Text(
              [
                a.str('status'),
                if (a.s('language') case final l?) l == 'r' ? 'R' : 'Python',
                if (a.s('next_action') case final n?) 'Next: $n',
                if (a.pending) 'waiting to sync',
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => context.push('/app/analyses/${a.id}'),
          ),
      ],
    );
  }
}
