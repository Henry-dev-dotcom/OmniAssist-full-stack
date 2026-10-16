import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared_widgets/async_state_view.dart';
import '../../shared_widgets/date_field.dart';
import '../records/records_repository.dart';
import '../sync/sync_controller.dart';
import 'experiments_tab.dart';

/// S19: draft, finalize and revise one experiment entry.
class ExperimentPage extends ConsumerWidget {
  const ExperimentPage({required this.entryId, super.key});
  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(recordProvider(entryId))
      .when(
        loading: () => const Scaffold(body: LoadingView()),
        error: (_, _) => const Scaffold(
          body: EmptyStateView(
            title: 'Cannot load entry',
            message: 'Restart the app. Your data is safe.',
          ),
        ),
        data: (e) => e == null
            ? Scaffold(
                appBar: AppBar(),
                body: const EmptyStateView(
                  title: 'Entry not found',
                  message: 'It may have been deleted on another device.',
                ),
              )
            : _Editor(key: ValueKey('${e.id}-${e.s('state')}'), e: e),
      );
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.e, super.key});
  final Rec e;
  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late final _title = TextEditingController(text: widget.e.str('title'));
  late final _c = {
    for (final (k, _) in experimentFields)
      k: TextEditingController(text: widget.e.str(k)),
  };
  late DateTime? _occurred = widget.e.dt('occurred_at')?.toLocal();
  // A finalized entry is read-only until the user starts a new revision.
  late bool _editing = widget.e.s('state') != 'finalized';
  Timer? _debounce;
  String _saved = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> _changes() {
    final e = widget.e;
    String? v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text;
    final occurred = _occurred == null
        ? null
        : DateTime(
            _occurred!.year,
            _occurred!.month,
            _occurred!.day,
            12,
          ).toUtc();
    return {
      if (_title.text.trim().isNotEmpty && _title.text.trim() != e.s('title'))
        'title': _title.text.trim(),
      for (final (k, _) in experimentFields)
        if (v(_c[k]!) != e.s(k)) k: v(_c[k]!),
      if (occurred != null &&
          occurred.toLocal().day != e.dt('occurred_at')?.toLocal().day)
        'occurred_at': occurred,
    };
  }

  /// Drafts autosave locally; autosave never finalizes (Spec 4.10).
  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _save);
  }

  Future<void> _save({Map<String, Object?> extra = const {}}) async {
    _debounce?.cancel();
    final changes = {..._changes(), ...extra};
    if (changes.isEmpty) return;
    await ref.read(recordsRepositoryProvider).change(widget.e.id, changes);
    ref.read(syncControllerProvider.notifier).syncNow();
    if (mounted) setState(() => _saved = 'Saved on this device');
  }

  Future<void> _finalize() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Finalize this entry?'),
        content: const Text(
          'A finalized entry is read-only. Later changes start a new revision, '
          'and this version is kept in the history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Finalize'),
          ),
        ],
      ),
    );
    if (ok == true) await _save(extra: {'state': 'finalized'});
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.e;
    final finalized = e.s('state') == 'finalized';
    final revisions =
        [
          for (final r
              in ref.watch(recordsProvider('experiment_revision')).value ??
                  const <Rec>[])
            if (r.s('entry_id') == e.id) r,
        ]..sort(
          (a, b) => (b.n('revision_number') ?? 0).compareTo(
            a.n('revision_number') ?? 0,
          ),
        );
    final readOnly = !_editing;
    return PopScope(
      // Leaving keeps the draft: pending edits save first (Spec 8.3).
      onPopInvokedWithResult: (_, _) {
        if (_editing) _save();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(e.str('title')),
          actions: [
            if (_saved.isNotEmpty && _editing)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(_saved),
                ),
              ),
            if (finalized && !_editing)
              FilledButton.tonal(
                onPressed: () => setState(() => _editing = true),
                child: const Text('Edit as new revision'),
              )
            else
              FilledButton(onPressed: _finalize, child: const Text('Finalize')),
            const SizedBox(width: 12),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 8),
                    Expanded(child: Text(notRegulatedNotice)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              finalized
                  ? (_editing
                        ? 'Editing starts revision ${(e.n('revision_number') ?? 1) + 1}. '
                              'Revision ${e.n('revision_number') ?? 1} stays in the history.'
                        : 'Finalized · revision ${e.n('revision_number') ?? 1} · read-only')
                  : 'Draft · revision ${e.n('revision_number') ?? 1} · autosaves on this device',
            ),
            TextField(
              controller: _title,
              readOnly: readOnly,
              maxLength: 240,
              onChanged: (_) => _scheduleSave(),
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            if (readOnly)
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Date'),
                child: Text(
                  _occurred == null
                      ? 'None'
                      : MaterialLocalizations.of(context)
                            .formatMediumDate(_occurred!),
                ),
              )
            else
              DateField(
                label: 'Date',
                value: _occurred,
                clearable: false,
                onChanged: (d) {
                  setState(() => _occurred = d);
                  _scheduleSave();
                },
              ),
            for (final (k, label) in experimentFields)
              TextField(
                controller: _c[k],
                readOnly: readOnly,
                minLines: 2,
                maxLines: 12,
                onChanged: (_) => _scheduleSave(),
                decoration: InputDecoration(labelText: label),
              ),
            const Divider(height: 32),
            Semantics(
              header: true,
              container: true,
              child: Text(
                'Finalized revisions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (revisions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'None yet. Each finalized version is kept here after it syncs.',
                ),
              ),
            for (final r in revisions)
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text('Revision ${r.n('revision_number')}'),
                subtitle: Text(
                  ((r.data['snapshot'] as Map<String, dynamic>?)?['title']
                          as String?) ??
                      '',
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _RevisionDialog(r),
                ),
              ),
            TextButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Delete this entry?'),
                    content: const Text(
                      'Finalized revisions stay on the server.',
                    ),
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
                _debounce?.cancel();
                await ref.read(recordsRepositoryProvider).remove(e.id);
                ref.read(syncControllerProvider.notifier).syncNow();
                if (context.mounted) context.pop();
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete entry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevisionDialog extends StatelessWidget {
  const _RevisionDialog(this.r);
  final Rec r;

  @override
  Widget build(BuildContext context) {
    final snap = (r.data['snapshot'] as Map<String, dynamic>?) ?? const {};
    return AlertDialog(
      title: Text('Revision ${r.n('revision_number')}: ${snap['title'] ?? ''}'),
      content: SizedBox(
        width: 560,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final (k, label) in experimentFields)
              if (snap[k] case final String v when v.isNotEmpty) ...[
                Text(label, style: Theme.of(context).textTheme.titleSmall),
                SelectableText(v),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
