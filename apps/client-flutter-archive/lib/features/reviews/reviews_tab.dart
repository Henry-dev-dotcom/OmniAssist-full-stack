import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../milestones/milestones_tab.dart';
import '../records/records_repository.dart';
import '../sync/sync_controller.dart';

const defaultStageNames = [
  'Protocol',
  'Screening',
  'Full Text',
  'Extraction',
  'Synthesis',
];

typedef Stage = ({String id, String name, bool archived});

/// A review's stages in order.
List<Stage> stagesOf(Rec review) => [
  for (final s in (review.data['stages'] as List<dynamic>? ?? const []))
    (
      id: '${(s as Map<String, dynamic>)['id']}',
      name: '${s['name']}',
      archived: s['archived'] == true,
    ),
];

class ReviewsTab extends ConsumerWidget {
  const ReviewsTab({required this.projectId, super.key});
  final String projectId;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final ws = ref.read(authControllerProvider).value?.workspaceId;
    final name = await askTitle(context, 'New systematic review');
    if (ws == null || name == null) return;
    final repo = ref.read(recordsRepositoryProvider);
    // Stage ids are made here so a review created offline is usable at once.
    final id = await repo.create(ws, 'review', {
      'project_id': projectId,
      'name': name,
      'stages': [
        for (final n in defaultStageNames)
          {'id': repo.newId(), 'name': n, 'archived': false},
      ],
    });
    ref.read(syncControllerProvider.notifier).syncNow();
    if (context.mounted) await context.push('/app/reviews/$id');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = [
      for (final r
          in ref.watch(recordsProvider('review')).value ?? const <Rec>[])
        if (r.s('project_id') == projectId) r,
    ];
    final items = ref.watch(recordsProvider('review_item')).value ?? const [];
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Screen studies through configurable stages. '
                  'Import and export with CSV.',
                ),
              ),
              FilledButton.icon(
                onPressed: () => _add(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Review'),
              ),
            ],
          ),
        ),
        if (reviews.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('No reviews in this project yet.'),
          ),
        for (final r in reviews)
          ListTile(
            leading: const Icon(Icons.view_kanban_outlined),
            title: Text(r.str('name')),
            subtitle: Text(
              [
                '${items.where((i) => i.s('review_id') == r.id).length} items',
                '${stagesOf(r).where((s) => !s.archived).length} stages',
                if (r.pending) 'waiting to sync',
              ].join(' · '),
            ),
            onTap: () => context.push('/app/reviews/${r.id}'),
          ),
      ],
    );
  }
}
