import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared_widgets/async_state_view.dart';
import '../../shared_widgets/file_io.dart';
import '../auth/auth_controller.dart';
import '../milestones/milestones_tab.dart';
import '../records/records_repository.dart';
import '../sync/sync_controller.dart';
import 'review_csv.dart';
import 'reviews_tab.dart';

/// S14: review board. Columns with counts on wide screens, a stage selector on narrow
/// ones. Dragging is an extra; every card also has a "Move to" menu (Spec 8.3).
class ReviewBoardPage extends ConsumerStatefulWidget {
  const ReviewBoardPage({required this.reviewId, super.key});
  final String reviewId;
  @override
  ConsumerState<ReviewBoardPage> createState() => _ReviewBoardPageState();
}

class _ReviewBoardPageState extends ConsumerState<ReviewBoardPage> {
  String? _stage; // narrow layout: the stage being shown

  Future<void> _move(String itemId, String stageId) async {
    await ref.read(recordsRepositoryProvider).change(itemId, {
      'stage_id': stageId,
    });
    ref.read(syncControllerProvider.notifier).syncNow();
  }

  Future<void> _addItem(Rec review, String stageId) async {
    final ws = ref.read(authControllerProvider).value?.workspaceId;
    final title = await askTitle(context, 'New item (title or citation)');
    if (ws == null || title == null) return;
    await ref.read(recordsRepositoryProvider).create(ws, 'review_item', {
      'review_id': review.id,
      'stage_id': stageId,
      'title': title,
      'tags': <String>[],
    });
    ref.read(syncControllerProvider.notifier).syncNow();
  }

  Future<void> _export(Rec review, List<Rec> items) async {
    final names = {for (final s in stagesOf(review)) s.id: s.name};
    final csv = encodeCsv([
      exportColumns,
      for (final i in items)
        [
          i.id,
          review.id,
          names[i.s('stage_id')],
          i.s('stage_id'),
          i.s('title'),
          i.s('source_identifier'),
          i.s('decision'),
          i.s('reviewer'),
          i.list('tags').join('; '),
          i.s('notes'),
          i.s('external_url'),
          i.row.updatedAt.toUtc().toIso8601String(),
        ],
    ]);
    final safe = review.str('name').replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    await saveTextFile('review_$safe.csv', csv, 'text/csv');
  }

  Future<void> _import(Rec review) async {
    final picked = await pickTextFile(
      extensions: const ['csv'],
      maxBytes: csvMaxBytes,
    );
    if (picked == null || !mounted) return;
    if (picked.error != null) {
      _snack(picked.error!);
      return;
    }
    final CsvTable table;
    try {
      table = parseCsv(picked.text!);
    } on FormatException catch (e) {
      _snack(e.message);
      return;
    }
    final active = [
      for (final s in stagesOf(review))
        if (!s.archived) s,
    ];
    final imported = await showDialog<int>(
      context: context,
      builder: (_) => _ImportDialog(
        review: review,
        table: table,
        fileName: picked.name ?? 'file',
        stages: active,
      ),
    );
    if (imported != null) {
      _snack('Imported $imported items. Saved on this device.');
      ref.read(syncControllerProvider.notifier).syncNow();
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final review = ref.watch(recordProvider(widget.reviewId));
    final allItems =
        ref.watch(recordsProvider('review_item')).value ?? const [];
    return review.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (_, _) => const Scaffold(
        body: EmptyStateView(
          title: 'Cannot load review',
          message: 'Restart the app. Your data is safe.',
        ),
      ),
      data: (r) {
        if (r == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyStateView(
              title: 'Review not found',
              message: 'It may have been deleted on another device.',
            ),
          );
        }
        final stages = [
          for (final s in stagesOf(r))
            if (!s.archived) s,
        ];
        final items = [
          for (final i in allItems)
            if (i.s('review_id') == r.id) i,
        ];
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final current = stages.any((s) => s.id == _stage)
            ? _stage!
            : (stages.isEmpty ? null : stages.first.id);
        return Scaffold(
          appBar: AppBar(
            title: Text(r.str('name')),
            actions: [
              IconButton(
                tooltip: 'Import CSV',
                icon: const Icon(Icons.upload_file),
                onPressed: () => _import(r),
              ),
              IconButton(
                tooltip: 'Export CSV',
                icon: const Icon(Icons.download),
                onPressed: () => _export(r, items),
              ),
              IconButton(
                tooltip: 'Manage stages',
                icon: const Icon(Icons.tune),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _StagesDialog(review: r, items: items),
                ),
              ),
            ],
          ),
          floatingActionButton: current == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () =>
                      _addItem(r, wide ? stages.first.id : current),
                  icon: const Icon(Icons.add),
                  label: const Text('Item'),
                ),
          body: stages.isEmpty
              ? const EmptyStateView(
                  title: 'No active stages',
                  message: 'Add a stage with Manage stages.',
                )
              : wide
              ? _Columns(stages: stages, items: items, onMove: _move)
              : _GroupedList(
                  stages: stages,
                  items: items,
                  current: current!,
                  onStage: (s) => setState(() => _stage = s),
                  onMove: _move,
                ),
        );
      },
    );
  }
}

class _Columns extends StatelessWidget {
  const _Columns({
    required this.stages,
    required this.items,
    required this.onMove,
  });
  final List<Stage> stages;
  final List<Rec> items;
  final Future<void> Function(String item, String stage) onMove;

  @override
  Widget build(BuildContext context) => ListView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.all(12),
    children: [
      for (final s in stages)
        DragTarget<String>(
          onAcceptWithDetails: (d) => onMove(d.data, s.id),
          builder: (context, candidates, _) {
            final mine = [
              for (final i in items)
                if (i.s('stage_id') == s.id) i,
            ];
            return Container(
              width: 280,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: candidates.isEmpty
                    ? Theme.of(context).colorScheme.surfaceContainerLow
                    : Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Semantics(
                      header: true,
                      container: true,
                      child: Text(
                        '${s.name} (${mine.length})',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        for (final i in mine)
                          Draggable<String>(
                            data: i.id,
                            feedback: SizedBox(
                              width: 260,
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(i.str('title')),
                                ),
                              ),
                            ),
                            child: ItemCard(
                              item: i,
                              stages: stages,
                              onMove: onMove,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
    ],
  );
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({
    required this.stages,
    required this.items,
    required this.current,
    required this.onStage,
    required this.onMove,
  });
  final List<Stage> stages;
  final List<Rec> items;
  final String current;
  final ValueChanged<String> onStage;
  final Future<void> Function(String item, String stage) onMove;

  @override
  Widget build(BuildContext context) {
    int count(String id) => items.where((i) => i.s('stage_id') == id).length;
    final mine = [
      for (final i in items)
        if (i.s('stage_id') == current) i,
    ];
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final s in stages)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${s.name} (${count(s.id)})'),
                    selected: s.id == current,
                    onSelected: (_) => onStage(s.id),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: mine.isEmpty
              ? const EmptyStateView(
                  title: 'Nothing in this stage',
                  message: 'Add items or move them here.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                  children: [
                    for (final i in mine)
                      ItemCard(item: i, stages: stages, onMove: onMove),
                  ],
                ),
        ),
      ],
    );
  }
}

/// One review item. The menu is the keyboard and touch path for moving it.
class ItemCard extends StatelessWidget {
  const ItemCard({
    required this.item,
    required this.stages,
    required this.onMove,
    super.key,
  });
  final Rec item;
  final List<Stage> stages;
  final Future<void> Function(String item, String stage) onMove;

  @override
  Widget build(BuildContext context) {
    final decision = item.s('decision');
    return Card(
      child: ListTile(
        title: Text(
          item.str('title'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            ?decision,
            ...item.list('tags'),
            if (item.pending) 'waiting to sync',
          ].join(' · '),
        ),
        onTap: () => context.push('/app/review-items/${item.id}'),
        trailing: PopupMenuButton<String>(
          tooltip: 'Move ${item.str('title')}',
          icon: const Icon(Icons.drive_file_move_outline),
          onSelected: (stage) => onMove(item.id, stage),
          itemBuilder: (_) => [
            for (final s in stages)
              if (s.id != item.s('stage_id'))
                PopupMenuItem(value: s.id, child: Text('Move to ${s.name}')),
          ],
        ),
      ),
    );
  }
}

/// Rename, reorder, add and archive stages (Spec 4.8). Names stay unique.
class _StagesDialog extends ConsumerStatefulWidget {
  const _StagesDialog({required this.review, required this.items});
  final Rec review;
  final List<Rec> items;
  @override
  ConsumerState<_StagesDialog> createState() => _StagesDialogState();
}

class _StagesDialogState extends ConsumerState<_StagesDialog> {
  late final List<({String id, TextEditingController name, bool archived})>
  _rows = [
    for (final s in stagesOf(widget.review))
      (
        id: s.id,
        name: TextEditingController(text: s.name),
        archived: s.archived,
      ),
  ];
  String? _error;

  @override
  void dispose() {
    for (final r in _rows) {
      r.name.dispose();
    }
    super.dispose();
  }

  void _swap(int i, int j) => setState(() {
    final t = _rows[i];
    _rows[i] = _rows[j];
    _rows[j] = t;
  });

  Future<void> _save() async {
    final names = [for (final r in _rows) r.name.text.trim()];
    String? error;
    if (names.any((n) => n.isEmpty || n.length > 80)) {
      error = 'Every stage needs a name of 1 to 80 characters.';
    } else if (names.map((n) => n.toLowerCase()).toSet().length !=
        names.length) {
      error = 'Stage names must be unique.';
    } else if (_rows.every((r) => r.archived)) {
      error = 'Keep at least one active stage.';
    } else {
      for (final r in _rows) {
        final has = widget.items.any((i) => i.s('stage_id') == r.id);
        if (r.archived && has) {
          error =
              'Move the items out of "${r.name.text.trim()}" before archiving it.';
          break;
        }
      }
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    await ref.read(recordsRepositoryProvider).change(widget.review.id, {
      'stages': [
        for (final r in _rows)
          {'id': r.id, 'name': r.name.text.trim(), 'archived': r.archived},
      ],
    });
    ref.read(syncControllerProvider.notifier).syncNow();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Stages'),
    content: SizedBox(
      width: 480,
      child: ListView(
        shrinkWrap: true,
        children: [
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          for (final (i, r) in _rows.indexed)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: r.name,
                    enabled: !r.archived,
                    decoration: InputDecoration(
                      labelText: r.archived
                          ? 'Archived stage'
                          : 'Stage ${i + 1}',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Move up',
                  onPressed: i == 0 ? null : () => _swap(i, i - 1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move down',
                  onPressed: i == _rows.length - 1
                      ? null
                      : () => _swap(i, i + 1),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: r.archived ? 'Restore stage' : 'Archive stage',
                  onPressed: () => setState(
                    () => _rows[i] = (
                      id: r.id,
                      name: r.name,
                      archived: !r.archived,
                    ),
                  ),
                  icon: Icon(
                    r.archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                ),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(
                () => _rows.add((
                  id: ref.read(recordsRepositoryProvider).newId(),
                  name: TextEditingController(text: 'New stage'),
                  archived: false,
                )),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add stage'),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}

/// Preview, map columns, see row errors, then import everything in one transaction.
class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog({
    required this.review,
    required this.table,
    required this.fileName,
    required this.stages,
  });
  final Rec review;
  final CsvTable table;
  final String fileName;
  final List<Stage> stages;
  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  late final Map<String, int?> _mapping = guessMapping(widget.table.headers);
  late String _defaultStage = widget.stages.first.id;
  bool _busy = false;

  List<ImportRow> get _plan => planImport(widget.table, _mapping, {
    for (final s in widget.stages) s.name: s.id,
  }, _defaultStage);

  Future<void> _apply(List<ImportRow> rows) async {
    final ws = ref.read(authControllerProvider).value?.workspaceId;
    if (ws == null) return;
    setState(() => _busy = true);
    final repo = ref.read(recordsRepositoryProvider);
    try {
      await repo.createAll(ws, [
        for (final r in rows)
          (
            type: 'review_item',
            id: repo.newId(),
            data: {...r.data, 'review_id': widget.review.id},
          ),
      ]);
      if (mounted) Navigator.pop(context, rows.length);
    } catch (_) {
      // One transaction: on failure nothing was written.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _mapping['title'] == null ? <ImportRow>[] : _plan;
    final bad = [
      for (final r in plan)
        if (r.errors.isNotEmpty) r,
    ];
    final headers = widget.table.headers;
    final error = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: Text('Import ${widget.fileName}'),
      content: SizedBox(
        width: 640,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              '${widget.table.rows.length} rows, ${headers.length} columns. '
              'Nothing is saved until you import.',
            ),
            const SizedBox(height: 12),
            Text('Columns', style: Theme.of(context).textTheme.titleSmall),
            for (final f in importFields.entries)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      f.value + (f.key == 'title' ? ' (required)' : ''),
                    ),
                  ),
                  Expanded(
                    child: DropdownButton<int?>(
                      isExpanded: true,
                      value: _mapping[f.key],
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Not imported'),
                        ),
                        for (final (i, h) in headers.indexed)
                          DropdownMenuItem(
                            value: i,
                            child: Text(h.isEmpty ? 'Column ${i + 1}' : h),
                          ),
                      ],
                      onChanged: (v) => setState(() => _mapping[f.key] = v),
                    ),
                  ),
                ],
              ),
            Row(
              children: [
                const Expanded(child: Text('Stage for rows without one')),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _defaultStage,
                    items: [
                      for (final s in widget.stages)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: (v) =>
                        setState(() => _defaultStage = v ?? _defaultStage),
                  ),
                ),
              ],
            ),
            const Divider(),
            if (_mapping['title'] == null)
              Text(
                'Choose the column that holds the title.',
                style: TextStyle(color: error),
              )
            else if (bad.isEmpty)
              Text('All ${plan.length} rows are valid.')
            else ...[
              Text(
                '${bad.length} of ${plan.length} rows need fixing in the file:',
                style: TextStyle(color: error),
              ),
              for (final r in bad.take(50))
                Text('Line ${r.line}: ${r.errors.join(' ')}'),
              if (bad.length > 50) Text('…and ${bad.length - 50} more.'),
            ],
            const SizedBox(height: 8),
            Text('Preview', style: Theme.of(context).textTheme.titleSmall),
            for (final r in plan.take(5))
              Text(
                '• ${r.data['title']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || plan.isEmpty || bad.isNotEmpty
              ? null
              : () => _apply(plan),
          child: Text('Import ${plan.length} items'),
        ),
      ],
    );
  }
}
