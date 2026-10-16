import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../records/records_repository.dart';
import '../sync/sync_controller.dart';

const notRegulatedNotice =
    'OmniAssist is not a validated or regulated electronic lab notebook. '
    'Keep official records where your institution requires them.';

/// Body fields in display order with their labels.
const experimentFields = <(String, String)>[
  ('objective', 'Objective'),
  ('protocol', 'Protocol'),
  ('variables', 'Variables'),
  ('materials', 'Materials'),
  ('observations', 'Observations'),
  ('deviations', 'Deviations'),
  ('result_summary', 'Result summary'),
  ('next_steps', 'Next steps'),
];

/// Starter fields per template (Spec 4.10).
const experimentTemplates = <String, (String, Map<String, String>)>{
  'qpcr': (
    'qPCR',
    {
      'objective': 'Quantify expression of … relative to …',
      'variables':
          'Target genes:\nReference genes:\nSamples / conditions:\n'
          'Biological replicates:\nTechnical replicates:',
      'materials':
          'Master mix (lot):\nPrimers (IDs, concentration):\nTemplate (cDNA, ng/well):\n'
          'Plate and instrument:',
      'protocol':
          '1. Thaw reagents on ice\n2. Prepare master mix\n3. Load plate (layout below)\n'
          '4. Cycling: 95 °C 2 min; 40 × (95 °C 15 s, 60 °C 1 min); melt curve\n\n'
          'Plate layout:',
      'observations': 'Ct values / melt curves:',
      'result_summary': 'ΔΔCt result:',
    },
  ),
  'primer_design': (
    'Primer design',
    {
      'objective': 'Design primers for … (gene / accession)',
      'variables':
          'Target sequence or accession:\nAmplicon size:\nTm target:\nGC % range:\n'
          'Exon junction spanning:',
      'protocol': 'Tool (e.g. Primer-BLAST):\nParameters:',
      'result_summary': 'Forward:\nReverse:\nProduct size:\nSpecificity check:',
    },
  ),
};

/// S18: experiment entries of one project.
class ExperimentsTab extends ConsumerWidget {
  const ExperimentsTab({required this.projectId, super.key});
  final String projectId;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final ws = ref.read(authControllerProvider).value?.workspaceId;
    final choice = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => const _NewEntryDialog(),
    );
    if (ws == null || choice == null) return;
    final (title, template) = choice;
    final repo = ref.read(recordsRepositoryProvider);
    final id = await repo.create(ws, 'experiment_entry', {
      'project_id': projectId,
      'title': title,
      'template_type': template,
      'occurred_at': repo.now,
      'state': 'draft',
      ...?experimentTemplates[template]?.$2,
    });
    ref.read(syncControllerProvider.notifier).syncNow();
    if (context.mounted) await context.push('/app/experiments/$id');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = [
      for (final e
          in ref.watch(recordsProvider('experiment_entry')).value ??
              const <Rec>[])
        if (e.s('project_id') == projectId) e,
    ]..sort((a, b) => b.str('occurred_at').compareTo(a.str('occurred_at')));
    final l = MaterialLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(child: Text(notRegulatedNotice)),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _add(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Entry'),
              ),
            ],
          ),
        ),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('No experiment entries yet.'),
          ),
        for (final e in entries)
          ListTile(
            leading: Icon(
              e.s('state') == 'finalized'
                  ? Icons.lock_outline
                  : Icons.edit_note,
            ),
            title: Text(e.str('title')),
            subtitle: Text(
              [
                if (e.dt('occurred_at') case final at?)
                  l.formatMediumDate(at.toLocal()),
                e.s('state') == 'finalized'
                    ? 'Finalized, revision ${e.n('revision_number') ?? 1}'
                    : 'Draft',
                if (experimentTemplates[e.s('template_type')] case final t?)
                  t.$1,
                if (e.pending) 'waiting to sync',
              ].join(' · '),
            ),
            onTap: () => context.push('/app/experiments/${e.id}'),
          ),
      ],
    );
  }
}

class _NewEntryDialog extends StatefulWidget {
  const _NewEntryDialog();
  @override
  State<_NewEntryDialog> createState() => _NewEntryDialogState();
}

class _NewEntryDialogState extends State<_NewEntryDialog> {
  final _title = TextEditingController();
  String? _template;
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
    Navigator.pop(context, (_title.text.trim(), _template));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New experiment entry'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _title,
          autofocus: true,
          maxLength: 240,
          decoration: InputDecoration(labelText: 'Title', errorText: _error),
        ),
        DropdownButtonFormField<String?>(
          initialValue: _template,
          decoration: const InputDecoration(labelText: 'Template'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Blank')),
            for (final t in experimentTemplates.entries)
              DropdownMenuItem(value: t.key, child: Text(t.value.$1)),
          ],
          onChanged: (v) => setState(() => _template = v),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Create draft')),
    ],
  );
}
