import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared_widgets/async_state_view.dart';
import '../activity/activity_view.dart';
import '../records/records_repository.dart';
import '../sync/sync_controller.dart';
import 'reviews_tab.dart';

/// S15: decision, notes and stage history for one review item.
class ReviewItemPage extends ConsumerWidget {
  const ReviewItemPage({required this.itemId, super.key});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(recordProvider(itemId));
    return item.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (_, _) => const Scaffold(
        body: EmptyStateView(
          title: 'Cannot load item',
          message: 'Restart the app. Your data is safe.',
        ),
      ),
      data: (i) => i == null
          ? Scaffold(
              appBar: AppBar(),
              body: const EmptyStateView(
                title: 'Item not found',
                message: 'It may have been deleted on another device.',
              ),
            )
          : _ItemEditor(key: ValueKey(i.id), item: i),
    );
  }
}

class _ItemEditor extends ConsumerStatefulWidget {
  const _ItemEditor({required this.item, super.key});
  final Rec item;
  @override
  ConsumerState<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends ConsumerState<_ItemEditor> {
  late final _title = TextEditingController(text: widget.item.str('title'));
  late final _source = TextEditingController(
    text: widget.item.str('source_identifier'),
  );
  late final _reviewer = TextEditingController(
    text: widget.item.str('reviewer'),
  );
  late final _tags = TextEditingController(
    text: widget.item.list('tags').join('; '),
  );
  late final _notes = TextEditingController(text: widget.item.str('notes'));
  late final _url = TextEditingController(
    text: widget.item.str('external_url'),
  );
  late String? _decision = widget.item.s('decision');
  late String? _stage = widget.item.s('stage_id');
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _source, _reviewer, _tags, _notes, _url]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    final i = widget.item;
    final title = _title.text.trim();
    final tags = [
      for (final t in _tags.text.split(';'))
        if (t.trim().isNotEmpty) t.trim(),
    ];
    final url = _opt(_url);
    final uri = url == null ? null : Uri.tryParse(url);
    final problem = title.isEmpty
        ? 'Enter a title.'
        : tags.any((t) => t.length > 60)
        ? 'Tags must be 60 characters or fewer.'
        : url != null &&
              (uri == null ||
                  !{'http', 'https'}.contains(uri.scheme) ||
                  uri.host.isEmpty)
        ? 'The link must start with http:// or https://.'
        : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final changes = <String, Object?>{
      if (title != i.s('title')) 'title': title,
      if (_opt(_source) != i.s('source_identifier'))
        'source_identifier': _opt(_source),
      if (_opt(_reviewer) != i.s('reviewer')) 'reviewer': _opt(_reviewer),
      if (tags.join('\u0000') != i.list('tags').join('\u0000')) 'tags': tags,
      if (_opt(_notes) != i.s('notes')) 'notes': _opt(_notes),
      if (url != i.s('external_url')) 'external_url': url,
      if (_decision != i.s('decision')) 'decision': _decision,
      if (_stage != i.s('stage_id')) 'stage_id': _stage,
    };
    if (changes.isNotEmpty) {
      await ref.read(recordsRepositoryProvider).change(i.id, changes);
      ref.read(syncControllerProvider.notifier).syncNow();
    }
    if (mounted) {
      setState(() => _error = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved on this device')));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this item?'),
        content: const Text('Its stage history stays on the server.'),
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
    await ref.read(recordsRepositoryProvider).remove(widget.item.id);
    ref.read(syncControllerProvider.notifier).syncNow();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final review = ref
        .watch(recordProvider(widget.item.str('review_id')))
        .value;
    final stages = review == null ? const <Stage>[] : stagesOf(review);
    final names = {
      for (final s in stages) s.id: s.name,
      widget.item.id: widget.item.str('title'),
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review item'),
        actions: [
          IconButton(
            tooltip: 'Delete item',
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
          TextField(
            controller: _title,
            maxLines: 3,
            minLines: 1,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Title or citation'),
          ),
          DropdownButtonFormField<String?>(
            initialValue: stages.any((s) => s.id == _stage) ? _stage : null,
            decoration: const InputDecoration(labelText: 'Stage'),
            items: [
              for (final s in stages)
                if (!s.archived || s.id == _stage)
                  DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) => setState(() => _stage = v ?? _stage),
          ),
          const SizedBox(height: 16),
          Text('Decision', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String?>(
            segments: const [
              ButtonSegment(value: null, label: Text('None')),
              ButtonSegment(value: 'include', label: Text('Include')),
              ButtonSegment(value: 'maybe', label: Text('Maybe')),
              ButtonSegment(value: 'exclude', label: Text('Exclude')),
            ],
            selected: {_decision},
            onSelectionChanged: (s) => setState(() => _decision = s.first),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _source,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Source ID (DOI, PMID…)',
            ),
          ),
          TextField(
            controller: _reviewer,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Reviewer'),
          ),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
              labelText: 'Tags',
              helperText: 'Separate tags with ;',
            ),
          ),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Link'),
          ),
          TextField(
            controller: _notes,
            maxLines: 8,
            minLines: 3,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          const Divider(height: 32),
          Semantics(
            header: true,
            container: true,
            child: Text(
              'Stage history',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ActivityList(
            entityIds: {widget.item.id},
            names: names,
            shrinkWrap: true,
          ),
        ],
      ),
    );
  }
}
