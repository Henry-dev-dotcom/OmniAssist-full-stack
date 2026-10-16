import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/database/app_database.dart';
import 'package:omniassist/features/records/records_repository.dart';
import 'package:omniassist/features/search/search_logic.dart';

final now = DateTime.utc(2026, 10, 16, 12);

Task task(
  String id,
  String title, {
  String? project,
  String priority = 'normal',
  DateTime? updated,
}) => Task(
  id: id,
  workspaceId: 'w1',
  version: 1,
  syncState: 'synced',
  createdAt: now,
  updatedAt: updated ?? now,
  title: title,
  status: 'planned',
  priority: priority,
  projectId: project,
);

Project project(String id, String name) => Project(
  id: id,
  workspaceId: 'w1',
  version: 1,
  syncState: 'synced',
  createdAt: now,
  updatedAt: now,
  name: name,
  category: 'thesis',
  status: 'planned',
  progressValue: 0,
);

Rec rec(String id, String type, Map<String, Object?> data) => Rec(
  RecordRow(
    id: id,
    workspaceId: 'w1',
    version: 1,
    syncState: 'synced',
    createdAt: now,
    updatedAt: now,
    entityType: type,
    data: jsonEncode(data),
  ),
);

List<SearchHit> run(
  String q, {
  SearchFilters filters = const SearchFilters(),
  List<Task>? tasks,
}) => searchLocal(
  query: q,
  filters: filters,
  tasks:
      tasks ??
      [
        task('t1', 'Write methods chapter', project: 'p1', priority: 'high'),
        task(
          't2',
          'Email supervisor about methods',
          updated: now.subtract(const Duration(days: 40)),
        ),
      ],
  projects: [project('p1', 'PhD thesis')],
  records: [
    rec('r1', 'review', {'project_id': 'p1', 'name': 'SLR'}),
    rec('i1', 'review_item', {
      'review_id': 'r1',
      'title': 'Smith 2020',
      'notes': 'mixed methods design',
      'tags': ['RCT'],
    }),
    rec('a1', 'analysis_record', {
      'project_id': 'p1',
      'title': 'Mixed model',
      'status': 'failed',
      'error_details': 'singular fit',
    }),
    rec('e1', 'experiment_entry', {
      'project_id': 'p1',
      'title': 'qPCR run',
      'state': 'draft',
      'observations': 'Ct 21',
    }),
    rec('m1', 'milestone', {
      'project_id': 'p1',
      'title': 'Chapter 2',
      'status': 'at_risk',
    }),
  ],
  now: now,
);

void main() {
  test('every word must match; title matches rank first', () {
    expect(run('methods').map((h) => h.id), ['t1', 't2', 'i1']);
    expect(run('mixed methods').map((h) => h.id), ['i1']);
    expect(run('SINGULAR').single.route, '/app/analyses/a1');
    expect(run('   '), isEmpty);
  });

  test('filters: type, project, status, priority, tag, date', () {
    expect(
      run(
        'methods',
        filters: const SearchFilters(types: {'task'}),
      ).map((h) => h.id),
      ['t1', 't2'],
    );
    expect(
      run(
        'methods',
        filters: const SearchFilters(projectId: 'p1'),
      ).map((h) => h.id),
      ['t1', 'i1'],
    );
    expect(
      run('model', filters: const SearchFilters(status: 'failed')).single.id,
      'a1',
    );
    expect(
      run('methods', filters: const SearchFilters(priority: 'high')).single.id,
      't1',
    );
    expect(
      run('smith', filters: const SearchFilters(tag: 'rct')).single.id,
      'i1',
    );
    expect(
      run(
        'methods',
        filters: const SearchFilters(updatedWithinDays: 30),
      ).map((h) => h.id),
      ['t1', 'i1'],
    );
  });

  test('local task search stays under 500 ms on 5,000 tasks (Spec 11.1)', () {
    final many = [
      for (var i = 0; i < 5000; i++)
        task(
          't$i',
          'Task $i ${i.isEven ? 'analysis' : 'writing'} chapter ${i % 12}',
        ),
    ];
    final watch = Stopwatch()..start();
    final hits = run('analysis chapter 3', tasks: many);
    watch.stop();
    expect(hits, isNotEmpty);
    expect(watch.elapsedMilliseconds, lessThan(500));
  });
}
