import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/database/app_database.dart';
import 'package:omniassist/features/milestones/milestone_rules.dart';
import 'package:omniassist/features/records/records_repository.dart';
import 'package:omniassist/features/today/today_briefing.dart';

final now = DateTime(2026, 10, 15, 10); // local wall time
final created = DateTime.utc(2026, 10, 1);

Task task(
  String id, {
  DateTime? due,
  String priority = 'normal',
  String status = 'planned',
  String? rule,
  String? milestone,
}) => Task(
  id: id,
  workspaceId: 'w1',
  version: 1,
  syncState: 'synced',
  createdAt: created,
  updatedAt: created,
  title: id,
  status: status,
  priority: priority,
  tags: '[]',
  dueAt: due?.toUtc(),
  recurrenceRule: rule,
  milestoneId: milestone,
);

TimeBlock block(String id, DateTime start, {String status = 'planned'}) =>
    TimeBlock(
      id: id,
      workspaceId: 'w1',
      version: 1,
      syncState: 'synced',
      createdAt: created,
      updatedAt: created,
      title: id,
      category: 'focus',
      startsAt: start.toUtc(),
      endsAt: start.add(const Duration(hours: 1)).toUtc(),
      status: status,
    );

Rec milestone(String id, Map<String, Object?> data) => Rec(
  RecordRow(
    id: id,
    workspaceId: 'w1',
    version: 1,
    syncState: 'synced',
    createdAt: created,
    updatedAt: created,
    entityType: 'milestone',
    data: jsonEncode({'title': id, 'status': 'in_progress', ...data}),
  ),
);

void main() {
  test('priorities: top 3 by priority then due, without duplicates', () {
    final b = buildBriefing(
      tasks: [
        task('low-today', due: now, priority: 'low'),
        task(
          'crit-later',
          due: now.add(const Duration(days: 9)),
          priority: 'critical',
        ),
        task('high', priority: 'high'),
        task('normal-today', due: now),
        task('old', due: now.subtract(const Duration(days: 3))),
        task('done', due: now, status: 'complete'),
        task('daily', rule: 'FREQ=DAILY', due: now),
      ],
      blocks: const [],
      milestones: const [],
      now: now,
    );
    expect(b.priorities.map((t) => t.id), ['crit-later', 'high', 'old']);
    expect(b.dueToday.map((t) => t.id), ['normal-today', 'low-today']);
    expect(b.overdue, isEmpty); // "old" is already a priority
    expect(b.routines.map((t) => t.id), ['daily']);
    final all = [...b.priorities, ...b.overdue, ...b.dueToday, ...b.routines];
    expect(all.map((t) => t.id).toSet().length, all.length);
  });

  test('blocks: today only, cancelled hidden, in start order', () {
    final b = buildBriefing(
      tasks: const [],
      blocks: [
        block('pm', DateTime(2026, 10, 15, 14)),
        block('am', DateTime(2026, 10, 15, 9)),
        block('tomorrow', DateTime(2026, 10, 16, 9)),
        block('off', DateTime(2026, 10, 15, 11), status: 'cancelled'),
      ],
      milestones: const [],
      now: now,
    );
    expect(b.blocks.map((x) => x.id), ['am', 'pm']);
  });

  test(
    'milestones: due soon or at risk, open only; overdue flagged not changed',
    () {
      final overdue = milestone('late', {'due_at': '2026-10-01T00:00:00Z'});
      final b = buildBriefing(
        tasks: const [],
        blocks: const [],
        milestones: [
          milestone('soon', {'due_at': '2026-10-20T00:00:00Z'}),
          milestone('far', {'due_at': '2027-03-01T00:00:00Z'}),
          milestone('blocked', {'status': 'blocked'}),
          milestone('finished', {
            'status': 'complete',
            'due_at': '2026-10-01T00:00:00Z',
          }),
          overdue,
        ],
        now: now,
      );
      expect(b.milestones.map((m) => m.id), ['late', 'soon', 'blocked']);
      expect(isMilestoneOverdue(overdue, now), isTrue);
      expect(overdue.s('status'), 'in_progress');
    },
  );

  test('empty data gives an empty briefing', () {
    expect(
      buildBriefing(
        tasks: const [],
        blocks: const [],
        milestones: const [],
        now: now,
      ).isEmpty,
      isTrue,
    );
  });

  test('progress: manual value, weighted children, linked tasks, 0..100', () {
    final parent = milestone('p', {'progress_mode': 'weighted'});
    final a = milestone('a', {
      'parent_id': 'p',
      'progress_value': 100,
      'weight': 3,
    });
    final b = milestone('b', {
      'parent_id': 'p',
      'progress_value': 0,
      'weight': 1,
    });
    final all = [parent, a, b];
    expect(milestoneProgress(parent, all, const []), 75);
    final solo = milestone('s', {'progress_mode': 'weighted'});
    final tasks = [
      task('t1', milestone: 's', status: 'complete'),
      task('t2', milestone: 's'),
    ];
    expect(milestoneProgress(solo, [solo], tasks), 50);
    expect(
      milestoneProgress(milestone('m', {'progress_value': 140}), [], []),
      100,
    );
  });
}
