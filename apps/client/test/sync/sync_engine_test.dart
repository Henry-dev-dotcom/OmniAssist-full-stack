import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omniassist/core/errors/error_codes.dart';
import 'package:omniassist/core/net/api_client.dart';
import 'package:omniassist/core/time/app_clock.dart';
import 'package:omniassist/database/app_database.dart';
import 'package:omniassist/features/projects/projects_repository.dart';
import 'package:omniassist/sync/backoff.dart';
import 'package:omniassist/sync/sync_engine.dart';

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'data': data, 'meta': <String, Object>{}}), 200);

void main() {
  late AppDatabase db;
  late FixedClock clock;
  late ProjectsRepository repo;
  late List<http.Request> sent;
  late http.Response Function(http.Request) server;

  SyncEngine engine() => SyncEngine(
        db,
        ApiClient(
          baseUrl: 'http://t/api/v1',
          client: MockClient((r) async {
            sent.add(r);
            return server(r);
          }),
        ),
        clock,
        random: Random(1),
      );

  Map<String, dynamic> pullPage(List<Map<String, dynamic>> changes,
          {int next = 0, bool more = false}) =>
      {'changes': changes, 'next_cursor': next, 'has_more': more, 'conflicts': <Object>[]};

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = FixedClock(DateTime.utc(2026, 10, 15, 12));
    repo = ProjectsRepository(db, clock);
    sent = [];
    server = (_) => _ok(pullPage([]));
  });
  tearDown(() => db.close());

  test('backoff follows the protocol schedule', () {
    final r = Random(7);
    int secs(int a) => retryDelay(a, random: r).inSeconds;
    expect(secs(1), inInclusiveRange(4, 6));
    expect(secs(2), inInclusiveRange(12, 18));
    expect(secs(3), inInclusiveRange(48, 72));
    expect(secs(4), inInclusiveRange(240, 360));
    expect(secs(5), inInclusiveRange(720, 1080));
    expect(secs(9), inInclusiveRange(1440, 2160)); // capped interval
  });

  test('accepted push clears the outbox and marks the row synced', () async {
    await repo.create('w1', 'Thesis', 'thesis');
    final m = (await db.syncDao.pending()).single;
    server = (r) => r.url.path.endsWith('/push')
        ? _ok({
            'results': [
              {'mutation_id': m.mutationId, 'status': 'accepted', 'entity_version': 1}
            ]
          })
        : _ok(pullPage([]));
    final out = await engine().syncOnce('u1');
    expect(out.ok, isTrue);
    expect(await db.syncDao.pending(), isEmpty);
    final row = (await repo.watchActive('w1').first).single;
    expect((row.syncState, row.version), ('synced', 1));
    final body = jsonDecode(sent.first.body) as Map<String, dynamic>;
    expect(body['protocol_version'], 1);
    expect((body['mutations'] as List).single['changes']['name'], 'Thesis');
  });

  test('network failure keeps the mutation and backs off', () async {
    await repo.create('w1', 'Thesis', 'thesis');
    server = (_) => throw http.ClientException('down');
    final e = engine();
    final out = await e.syncOnce('u1');
    expect(out.error?.code, ErrorCode.dependencyUnavailable);
    final m = (await db.syncDao.pending()).single;
    expect(m.attemptCount, 1);
    expect(m.nextAttemptAt!.isAfter(clock.now()), isTrue);
    // Not due yet: a second run sends no push.
    sent.clear();
    await e.syncOnce('u1');
    expect(sent.where((r) => r.url.path.endsWith('/push')), isEmpty);
    // After the wait it is due again.
    clock.advance(const Duration(minutes: 1));
    expect(await db.syncDao.due(clock.now()), hasLength(1));
  });

  test('conflict result is recorded and not retried', () async {
    await repo.create('w1', 'Thesis', 'thesis');
    final m = (await db.syncDao.pending()).single;
    server = (r) => r.url.path.endsWith('/push')
        ? _ok({
            'results': [
              {
                'mutation_id': m.mutationId,
                'status': 'conflict',
                'conflict_id': 'c1',
                'server': {'name': 'Server name'}
              }
            ]
          })
        : _ok(pullPage([]));
    await engine().syncOnce('u1');
    expect(await db.syncDao.pending(), isEmpty);
    expect(await db.syncDao.watchOpenConflictCount().first, 1);
    expect((await db.projectDao.byId(m.entityId))!.syncState, 'conflict');
  });

  test('rejected result is marked and not retried', () async {
    await repo.create('w1', 'Thesis', 'thesis');
    final m = (await db.syncDao.pending()).single;
    server = (r) => r.url.path.endsWith('/push')
        ? _ok({
            'results': [
              {
                'mutation_id': m.mutationId,
                'status': 'rejected',
                'error_code': 'VALIDATION_ERROR'
              }
            ]
          })
        : _ok(pullPage([]));
    await engine().syncOnce('u1');
    expect(await db.syncDao.due(clock.now().add(const Duration(days: 1))), isEmpty);
    expect((await db.projectDao.byId(m.entityId))!.syncState, 'rejected');
  });

  test('pull applies create, update and delete and stores the cursor', () async {
    Map<String, dynamic> change(int seq, String op, Map<String, dynamic>? p,
            {int v = 1}) =>
        {
          'sequence': seq,
          'workspace_id': 'w1',
          'entity_type': 'project',
          'entity_id': 'p1',
          'operation': op,
          'entity_version': v,
          'payload': p,
        };
    server = (_) => _ok(pullPage([
          change(5, 'create', {
            'name': 'Remote',
            'category': 'thesis',
            'status': 'planned',
            'progress_value': 10.0,
            'updated_at': '2026-10-14T00:00:00Z'
          }),
          change(6, 'update', {'status': 'in_progress'}, v: 2),
        ], next: 6));
    await engine().syncOnce('u1');
    final row = (await repo.watchActive('w1').first).single;
    expect((row.name, row.status, row.version, row.progressValue),
        ('Remote', 'in_progress', 2, 10));
    final device = (await db.syncDao.existingDeviceId())!;
    expect(await db.syncDao.cursorFor(device), 6);

    server = (_) => _ok(pullPage([change(7, 'delete', null, v: 3)], next: 7));
    await engine().syncOnce('u1');
    expect(await repo.watchActive('w1').first, isEmpty);
    expect(await db.syncDao.cursorFor(device), 7);
  });

  test('pull follows has_more until the feed is drained', () async {
    var calls = 0;
    server = (r) {
      calls++;
      return _ok(calls == 1
          ? pullPage([], next: 10, more: true)
          : pullPage([], next: 20));
    };
    await engine().syncOnce('u1');
    expect(calls, 2);
    expect(sent.last.url.queryParameters['cursor'], '10');
  });

  test('pulled change never overwrites a field with an unsent local edit',
      () async {
    await db.into(db.projects).insert(ProjectsCompanion.insert(
        id: 'p1',
        workspaceId: 'w1',
        name: 'Local',
        category: 'thesis',
        createdAt: clock.now(),
        updatedAt: clock.now(),
        version: const Value(1)));
    await repo.setArchived('p1', true); // pending: status=archived
    server = (r) => r.url.path.endsWith('/push')
        ? throw http.ClientException('down')
        : _ok(pullPage([
            {
              'sequence': 1,
              'workspace_id': 'w1',
              'entity_type': 'project',
              'entity_id': 'p1',
              'operation': 'update',
              'entity_version': 2,
              'payload': {'status': 'on_hold', 'name': 'Server rename'}
            }
          ], next: 1));
    // Push fails first, so apply the pull page directly.
    await db.syncDao.ensureState('d1', 'u1');
    await db.syncDao.applyPulledPage(deviceId: 'd1', changes: [
      {
        'sequence': 1,
        'workspace_id': 'w1',
        'entity_type': 'project',
        'entity_id': 'p1',
        'operation': 'update',
        'entity_version': 2,
        'payload': {'status': 'on_hold', 'name': 'Server rename'}
      }
    ], nextCursor: 1, now: clock.now());
    final row = (await db.projectDao.byId('p1'))!;
    expect(row.status, 'archived'); // local edit kept
    expect(row.name, 'Server rename'); // untouched field merged
    expect(row.version, 2);
  });

  test('a new account on the same device restarts from cursor 0', () async {
    await db.syncDao.ensureState('d1', 'u1');
    await db.syncDao.applyPulledPage(
        deviceId: 'd1', changes: [], nextCursor: 9, now: clock.now());
    await db.syncDao.ensureState('d1', 'u2');
    expect(await db.syncDao.cursorFor('d1'), 0);
  });
}
