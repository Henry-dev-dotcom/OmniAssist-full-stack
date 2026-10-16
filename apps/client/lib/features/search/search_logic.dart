import '../../database/app_database.dart';
import '../records/records_repository.dart';
import '../tasks/tasks_repository.dart';

/// Searchable entity types with their labels (Spec 4.11).
const searchTypes = <String, String>{
  'task': 'Tasks',
  'project': 'Projects',
  'milestone': 'Milestones',
  'review_item': 'Review items',
  'analysis_record': 'Analyses',
  'experiment_entry': 'Experiments',
};

class SearchFilters {
  const SearchFilters({
    this.types = const {},
    this.projectId,
    this.status,
    this.priority,
    this.tag,
    this.updatedWithinDays,
  });
  final Set<String> types; // empty = all
  final String? projectId;
  final String? status;
  final String? priority;
  final String? tag;
  final int? updatedWithinDays;
}

class SearchHit {
  const SearchHit({
    required this.type,
    required this.id,
    required this.title,
    required this.route,
    required this.updatedAt,
    this.projectId,
    this.status,
    this.priority,
    this.tags = const [],
    this.titleMatch = false,
  });
  final String type;
  final String id;
  final String title;
  final String route;
  final DateTime updatedAt;
  final String? projectId;
  final String? status;
  final String? priority;
  final List<String> tags;
  final bool titleMatch;
}

const _recordBody = <String, List<String>>{
  'milestone': ['title', 'description'],
  'review_item': ['title', 'notes', 'source_identifier', 'reviewer'],
  'analysis_record': [
    'title',
    'purpose',
    'result_summary',
    'error_details',
    'next_action',
    'environment',
  ],
  'experiment_entry': [
    'title',
    'objective',
    'protocol',
    'observations',
    'result_summary',
    'next_steps',
  ],
};

const _recordRoutes = {
  'milestone': '/app/milestones',
  'review_item': '/app/review-items',
  'analysis_record': '/app/analyses',
  'experiment_entry': '/app/experiments',
};

/// Searches local data only, so it works offline. Every word of [query] must appear
/// somewhere in the item; title matches rank first, then the most recently changed.
List<SearchHit> searchLocal({
  required String query,
  required SearchFilters filters,
  required List<Task> tasks,
  required List<Project> projects,
  required List<Rec> records,
  required DateTime now,
  int limit = 100,
}) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return const [];
  bool want(String type) =>
      filters.types.isEmpty || filters.types.contains(type);
  // Review items belong to a project through their review.
  final reviewProject = {
    for (final r in records)
      if (r.type == 'review') r.id: r.s('project_id'),
  };

  final hits = <SearchHit>[];
  void consider(SearchHit hit, String haystack) {
    final hay = haystack.toLowerCase();
    if (!words.every(hay.contains)) return;
    final f = filters;
    if (f.projectId != null && hit.projectId != f.projectId) return;
    if (f.status != null && hit.status != f.status) return;
    if (f.priority != null && hit.priority != f.priority) return;
    if (f.tag != null &&
        !hit.tags.any((t) => t.toLowerCase() == f.tag!.toLowerCase())) {
      return;
    }
    if (f.updatedWithinDays != null &&
        hit.updatedAt.isBefore(
          now.subtract(Duration(days: f.updatedWithinDays!)),
        )) {
      return;
    }
    final t = hit.title.toLowerCase();
    hits.add(
      SearchHit(
        type: hit.type,
        id: hit.id,
        title: hit.title,
        route: hit.route,
        updatedAt: hit.updatedAt,
        projectId: hit.projectId,
        status: hit.status,
        priority: hit.priority,
        tags: hit.tags,
        titleMatch: words.every(t.contains),
      ),
    );
  }

  if (want('task')) {
    for (final t in tasks) {
      if (t.deletedAt != null) continue;
      consider(
        SearchHit(
          type: 'task',
          id: t.id,
          title: t.title,
          route: '/app/tasks/${t.id}',
          updatedAt: t.updatedAt,
          projectId: t.projectId,
          status: t.status,
          priority: t.priority,
          tags: tagsOf(t),
        ),
        '${t.title}\n${t.description ?? ''}\n${tagsOf(t).join(' ')}',
      );
    }
  }
  if (want('project')) {
    for (final p in projects) {
      if (p.deletedAt != null) continue;
      consider(
        SearchHit(
          type: 'project',
          id: p.id,
          title: p.name,
          route: '/app/projects/${p.id}',
          updatedAt: p.updatedAt,
          projectId: p.id,
          status: p.status,
        ),
        '${p.name}\n${p.description ?? ''}\n${p.category}',
      );
    }
  }
  for (final r in records) {
    final fields = _recordBody[r.type];
    if (fields == null || !want(r.type) || r.row.deletedAt != null) continue;
    consider(
      SearchHit(
        type: r.type,
        id: r.id,
        title: r.str('title', '(untitled)'),
        route: '${_recordRoutes[r.type]}/${r.id}',
        updatedAt: r.row.updatedAt,
        projectId: r.type == 'review_item'
            ? reviewProject[r.s('review_id')]
            : r.s('project_id'),
        status: r.s('status') ?? r.s('state') ?? r.s('decision'),
        tags: r.list('tags'),
      ),
      [for (final f in fields) r.str(f), ...r.list('tags')].join('\n'),
    );
  }
  hits.sort((a, b) {
    if (a.titleMatch != b.titleMatch) return a.titleMatch ? -1 : 1;
    return b.updatedAt.compareTo(a.updatedAt);
  });
  return hits.take(limit).toList();
}
