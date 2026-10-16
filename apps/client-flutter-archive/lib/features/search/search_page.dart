import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../database/app_database.dart';
import '../auth/auth_controller.dart';
import '../milestones/milestones_tab.dart';
import '../records/records_repository.dart';
import 'search_logic.dart';

final _projectsProvider = StreamProvider.autoDispose<List<Project>>((ref) {
  final ws = ref.watch(authControllerProvider).value?.workspaceId;
  if (ws == null) return const Stream.empty();
  final dao = ref.watch(databaseProvider).projectDao;
  return dao.watchActive(ws);
});

/// Every record-backed entity in the workspace, re-read when the screen opens.
final _recordsProvider = FutureProvider.autoDispose<List<Rec>>((ref) async {
  final ws = ref.watch(authControllerProvider).value?.workspaceId;
  if (ws == null) return const [];
  return [
    for (final r in await ref.watch(databaseProvider).recordDao.allLive(ws))
      Rec(r),
  ];
});

/// S20: searches this device first, so it works offline (Spec 4.11).
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _q = TextEditingController();
  Set<String> _types = {};
  String? _project;
  String? _status;
  String? _priority;
  int? _days;
  String? _tag;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(workspaceTasksProvider).value ?? const [];
    final projects = ref.watch(_projectsProvider).value ?? const [];
    final records = ref.watch(_recordsProvider).value ?? const [];
    final filters = SearchFilters(
      types: _types,
      projectId: _project,
      status: _status,
      priority: _priority,
      tag: _tag,
      updatedWithinDays: _days,
    );
    final hits = searchLocal(
      query: _q.text,
      filters: filters,
      tasks: tasks,
      projects: projects,
      records: records,
      now: ref.watch(clockProvider).now(),
    );
    final projectNames = {for (final p in projects) p.id: p.name};
    final statuses = {
      ...['inbox', 'planned', 'in_progress', 'complete', 'failed', 'running'],
      'succeeded',
      'draft',
      'finalized',
      'at_risk',
      'blocked',
      'include',
      'exclude',
    }.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _q,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText:
                'Search tasks, projects, milestones, reviews, analyses, notes',
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search),
          ),
        ),
        actions: [
          if (_q.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              icon: const Icon(Icons.clear),
              onPressed: () => setState(_q.clear),
            ),
        ],
      ),
      body: ListView(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final t in searchTypes.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(t.value),
                      selected: _types.contains(t.key),
                      onSelected: (on) => setState(() {
                        _types = {..._types};
                        on ? _types.add(t.key) : _types.remove(t.key);
                      }),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Pick<String>(
                  label: 'Project',
                  value: _project,
                  options: {for (final p in projects) p.id: p.name},
                  onChanged: (v) => setState(() => _project = v),
                ),
                _Pick<String>(
                  label: 'Status',
                  value: _status,
                  options: {
                    for (final s in statuses) s: s.replaceAll('_', ' '),
                  },
                  onChanged: (v) => setState(() => _status = v),
                ),
                _Pick<String>(
                  label: 'Priority',
                  value: _priority,
                  options: const {
                    'critical': 'critical',
                    'high': 'high',
                    'normal': 'normal',
                    'low': 'low',
                  },
                  onChanged: (v) => setState(() => _priority = v),
                ),
                _Pick<int>(
                  label: 'Changed',
                  value: _days,
                  options: const {
                    7: 'last 7 days',
                    30: 'last 30 days',
                    365: 'last year',
                  },
                  onChanged: (v) => setState(() => _days = v),
                ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Tag',
                      isDense: true,
                    ),
                    onChanged: (v) => setState(
                      () => _tag = v.trim().isEmpty ? null : v.trim(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_q.text.trim().isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Type to search everything on this device, even offline.',
              ),
            )
          else if (hits.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No matches.'),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Semantics(
                liveRegion: true,
                child: Text('${hits.length} results on this device'),
              ),
            ),
            for (final h in hits)
              ListTile(
                leading: Icon(_icon(h.type)),
                title: Text(h.title),
                subtitle: Text(
                  [
                    searchTypes[h.type]!.replaceFirst(RegExp(r's$'), ''),
                    if (h.status != null) h.status!.replaceAll('_', ' '),
                    ?projectNames[h.projectId],
                  ].join(' · '),
                ),
                onTap: () => context.push(h.route),
              ),
          ],
        ],
      ),
    );
  }

  static IconData _icon(String type) => switch (type) {
    'task' => Icons.check_box_outlined,
    'project' => Icons.folder_outlined,
    'milestone' => Icons.flag_outlined,
    'review_item' => Icons.article_outlined,
    'analysis_record' => Icons.analytics_outlined,
    _ => Icons.science_outlined,
  };
}

class _Pick<T> extends StatelessWidget {
  const _Pick({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final T? value;
  final Map<T, String> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButton<T?>(
    value: options.containsKey(value) ? value : null,
    hint: Text(label),
    items: [
      DropdownMenuItem<T?>(
        value: null,
        child: Text('Any ${label.toLowerCase()}'),
      ),
      for (final o in options.entries)
        DropdownMenuItem<T?>(value: o.key, child: Text(o.value)),
    ],
    onChanged: onChanged,
  );
}
