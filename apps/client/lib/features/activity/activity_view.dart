import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../records/records_repository.dart';

const _typeLabels = {
  'project': 'Project',
  'task': 'Task',
  'time_block': 'Time block',
  'milestone': 'Milestone',
  'review': 'Review',
  'review_item': 'Review item',
  'analysis_record': 'Analysis',
  'experiment_entry': 'Experiment',
};

String _words(Object? v) => '$v'.replaceAll('_', ' ');

/// One readable line per event. Names come from [names] (ids to titles or stage names),
/// so the server never has to store content in activity metadata.
String describeActivity(Rec e, Map<String, String> names) {
  final meta = (e.data['metadata'] as Map<String, dynamic>?) ?? const {};
  String move(String key) {
    final m = meta[key] as Map<String, dynamic>?;
    if (m == null) return '';
    String name(Object? v) => v == null ? 'none' : names['$v'] ?? _words(v);
    return ': ${name(m['from'])} → ${name(m['to'])}';
  }

  return switch (e.s('action')) {
    'created' => 'Created',
    'deleted' => 'Deleted',
    'completed' => 'Completed',
    'finalized' => 'Finalized',
    'moved' => 'Moved${move('stage_id')}',
    'status_changed' => 'Status${move('status')}',
    'conflict_resolved' => 'Conflict resolved: ${_words(meta['resolution'])}',
    _ => () {
      final fields = ((meta['fields'] as List<dynamic>?) ?? const [])
          .map(_words)
          .join(', ');
      return fields.isEmpty ? 'Updated' : 'Updated $fields';
    }(),
  };
}

/// Activity for the given entities, newest first (Spec 4.7 timeline).
class ActivityList extends ConsumerWidget {
  const ActivityList({
    required this.entityIds,
    this.names = const {},
    this.shrinkWrap = false,
    this.limit,
    super.key,
  });

  final Set<String> entityIds;

  /// Ids to display names: entity titles and review stage names.
  final Map<String, String> names;
  final bool shrinkWrap;
  final int? limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events =
        ref.watch(recordsProvider('activity_event')).value ?? const [];
    final mine = [
      for (final e in events)
        if (entityIds.contains(e.s('entity_id'))) e,
    ]..sort((a, b) => b.str('created_at').compareTo(a.str('created_at')));
    final shown = limit == null ? mine : mine.take(limit!).toList();
    if (shown.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No history yet. Changes appear here after they sync.'),
      );
    }
    final l = MaterialLocalizations.of(context);
    final tiles = [
      for (final e in shown)
        ListTile(
          dense: true,
          leading: const Icon(Icons.history, size: 20),
          title: Text(describeActivity(e, names)),
          subtitle: Text(
            [
              _typeLabels[e.s('entity_type')] ?? _words(e.s('entity_type')),
              ?names[e.s('entity_id')],
              if (e.dt('created_at') case final at?)
                '${l.formatMediumDate(at.toLocal())} '
                    '${l.formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal()))}',
            ].join(' · '),
          ),
        ),
    ];
    return shrinkWrap ? Column(children: tiles) : ListView(children: tiles);
  }
}
