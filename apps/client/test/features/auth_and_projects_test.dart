import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omniassist/core/errors/error_codes.dart';
import 'package:omniassist/core/net/api_client.dart';
import 'package:omniassist/core/result/result.dart';
import 'package:omniassist/core/time/app_clock.dart';
import 'package:omniassist/database/app_database.dart';
import 'package:omniassist/features/auth/auth_repository.dart';
import 'package:omniassist/features/auth/token_store.dart';
import 'package:omniassist/features/projects/projects_repository.dart';

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'data': data, 'meta': <String, Object>{}}), 200);
http.Response _err(int code, String wire) => http.Response(
  jsonEncode({
    'error': {'code': wire, 'message': 'nope', 'retryable': false},
  }),
  code,
);

void main() {
  group('auth', () {
    late MemoryTokenStore store;
    late List<String> calls;

    AuthRepository build(http.Response Function(http.Request) handler) {
      calls = [];
      store = MemoryTokenStore();
      final client = MockClient((r) async {
        calls.add('${r.method} ${r.url.path}');
        return handler(r);
      });
      return AuthRepository(
        ApiClient(baseUrl: 'http://t/api/v1', client: client),
        store,
      );
    }

    http.Response happy(http.Request r) => switch (r.url.path) {
      '/api/v1/auth/login' => _ok({
        'access_token': 'a1',
        'refresh_token': 'r1',
        'expires_in': 60,
      }),
      '/api/v1/me' => _ok({'id': 'u1'}),
      '/api/v1/workspaces' when r.method == 'GET' => _ok([]),
      '/api/v1/workspaces' => _ok({'id': 'w1'}),
      _ => _err(404, 'NOT_FOUND'),
    };

    test('sign in stores refresh token and creates first workspace', () async {
      final repo = build(happy);
      final r = await repo.signIn('a@b.co', 'pw');
      expect(r, isA<Ok<Session>>());
      expect((r as Ok<Session>).value.workspaceId, 'w1');
      expect(await store.readRefreshToken(), 'r1');
      expect(repo.accessToken, 'a1');
    });

    test('register posts the name and signs in like login', () async {
      Object? sent;
      final repo = build((r) {
        if (r.url.path == '/api/v1/auth/register') {
          sent = jsonDecode(r.body);
          return _ok({
            'access_token': 'a1',
            'refresh_token': 'r1',
            'expires_in': 60,
          });
        }
        return happy(r);
      });
      final r = await repo.register('a@b.co', 'longenough', 'Ada');
      expect((r as Ok<Session>).value.workspaceId, 'w1');
      expect(sent, {
        'email': 'a@b.co',
        'password': 'longenough',
        'display_name': 'Ada',
      });
      expect(await store.readRefreshToken(), 'r1');
    });

    test('bad password returns an error and stores nothing', () async {
      final repo = build((_) => _err(401, 'UNAUTHENTICATED'));
      final r = await repo.signIn('a@b.co', 'bad');
      expect((r as Err<Session>).error.code, ErrorCode.unauthenticated);
      expect(await store.readRefreshToken(), isNull);
    });

    test('network failure is DEPENDENCY_UNAVAILABLE, not a crash', () async {
      final repo = build((_) => throw http.ClientException('down'));
      final r = await repo.signIn('a@b.co', 'pw');
      expect((r as Err<Session>).error.code, ErrorCode.dependencyUnavailable);
    });

    test('rejected refresh token clears the store', () async {
      final repo = build((_) => _err(401, 'UNAUTHENTICATED'));
      await store.writeRefreshToken('old');
      expect(await repo.refresh(), isFalse);
      expect(await store.readRefreshToken(), isNull);
    });

    test('offline refresh keeps the stored token', () async {
      final repo = build((_) => throw http.ClientException('down'));
      await store.writeRefreshToken('old');
      expect(await repo.refresh(), isFalse);
      expect(await store.readRefreshToken(), 'old');
    });

    test('offline start with a remembered session opens local data', () async {
      final repo = build((_) => throw http.ClientException('down'));
      await store.writeRefreshToken('old');
      await store.writeSession('u1 w1');
      final r = await repo.restore();
      expect((r as Ok<Session>).value.workspaceId, 'w1');
    });

    test('a rejected token never opens the cached session', () async {
      final repo = build((_) => _err(401, 'UNAUTHENTICATED'));
      await store.writeRefreshToken('old');
      await store.writeSession('u1 w1');
      expect(await repo.restore(), isA<Err<Session>>());
      expect(await store.readSession(), isNull);
    });

    test('offline without a remembered session asks to sign in', () async {
      final repo = build((_) => throw http.ClientException('down'));
      await store.writeRefreshToken('old');
      expect(await repo.restore(), isA<Err<Session>>());
    });

    test('sign in remembers the session for offline starts', () async {
      final repo = build(happy);
      await repo.signIn('a@b.co', 'pw');
      expect(await store.readSession(), 'u1 w1');
    });

    test(
      'the chosen workspace is reopened, or the first if it is gone',
      () async {
        http.Response two(http.Request r) => r.url.path == '/api/v1/workspaces'
            ? _ok([
                {'id': 'w1'},
                {'id': 'w2'},
              ])
            : happy(r);
        final repo = build(two);
        await repo.useWorkspace('u1', 'w2');
        final s = (await repo.signIn('a@b.co', 'pw') as Ok<Session>).value;
        expect(s.workspaceId, 'w2');
        await repo.useWorkspace('u1', 'deleted');
        final t = (await repo.signIn('a@b.co', 'pw') as Ok<Session>).value;
        expect(t.workspaceId, 'w1');
      },
    );

    test('changing the password keeps this device signed in', () async {
      final repo = build(
        (r) => r.url.path == '/api/v1/auth/change-password'
            ? _ok({'access_token': 'a9', 'refresh_token': 'r9'})
            : happy(r),
      );
      await repo.signIn('a@b.co', 'pw');
      expect(await repo.changePassword('pw', 'longer-pw'), isNull);
      expect((repo.accessToken, await store.readRefreshToken()), ('a9', 'r9'));
    });

    test('a wrong current password is reported, tokens untouched', () async {
      final repo = build((_) => _err(400, 'VALIDATION_ERROR'));
      await store.writeRefreshToken('keep');
      final err = await repo.changePassword('bad', 'longer-pw');
      expect(err?.code, ErrorCode.validationError);
      expect(await store.readRefreshToken(), 'keep');
    });

    test('expired access token refreshes once and retries', () async {
      var meCalls = 0;
      final repo = build((r) {
        switch (r.url.path) {
          case '/api/v1/auth/refresh':
            return _ok({'access_token': 'a2', 'refresh_token': 'r2'});
          case '/api/v1/me':
            return ++meCalls == 1
                ? _err(401, 'UNAUTHENTICATED')
                : _ok({'id': 'u1'});
          case '/api/v1/workspaces':
            return _ok([
              {'id': 'w1'},
            ]);
        }
        return _err(404, 'NOT_FOUND');
      });
      await store.writeRefreshToken('r1');
      final r = await repo.restore();
      expect(r, isA<Ok<Session>>());
      expect(await store.readRefreshToken(), 'r2');
    });

    test('sign out clears the token even when the server is down', () async {
      final repo = build(happy);
      await repo.signIn('a@b.co', 'pw');
      final down = build((_) => throw http.ClientException('down'));
      await store.writeRefreshToken('r1');
      await down.signOut();
      expect(await store.readRefreshToken(), isNull);
    });
  });

  group('projects', () {
    late AppDatabase db;
    late ProjectsRepository repo;
    final clock = FixedClock(DateTime.utc(2026, 10, 15));

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = ProjectsRepository(db, clock);
    });
    tearDown(() => db.close());

    test('create writes locally and queues one mutation', () async {
      await repo.create('w1', '  Thesis  ', 'thesis');
      final rows = await repo.watchActive('w1').first;
      expect(rows.single.name, 'Thesis');
      expect(rows.single.syncState, 'pending_create');
      expect(await db.syncDao.pending(), hasLength(1));
    });

    test('archive moves a project between views', () async {
      await repo.create('w1', 'A', 'personal');
      final id = (await repo.watchActive('w1').first).single.id;
      await repo.setArchived(id, true);
      expect(await repo.watchActive('w1').first, isEmpty);
      expect((await repo.watchArchived('w1').first).single.id, id);
      await repo.setArchived(id, false);
      expect(await repo.watchArchived('w1').first, isEmpty);
    });
  });
}
