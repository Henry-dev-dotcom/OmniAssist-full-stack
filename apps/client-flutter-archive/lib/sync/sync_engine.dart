import 'dart:convert';
import 'dart:math';

import '../core/errors/app_error.dart';
import '../core/errors/error_codes.dart';
import '../core/ids/entity_ids.dart';
import '../core/net/api_client.dart';
import '../core/time/app_clock.dart';
import '../database/app_database.dart';
import 'backoff.dart';

class SyncOutcome {
  const SyncOutcome({this.error, this.pushed = 0, this.pulled = 0});
  final AppError? error;
  final int pushed;
  final int pulled;
  bool get ok => error == null;
}

/// Uploads the outbox, then pulls the change feed (sync_protocol.md).
/// Safe to call often: concurrent calls share one run.
class SyncEngine {
  SyncEngine(this._db, this._api, this._clock, {Random? random})
    : _random = random ?? Random();

  final AppDatabase _db;
  final ApiClient _api;
  final AppClock _clock;
  final Random _random;
  Future<SyncOutcome>? _running;

  Future<SyncOutcome> syncOnce(String accountId) =>
      _running ??= _run(accountId).whenComplete(() => _running = null);

  Future<SyncOutcome> _run(String accountId) async {
    final dao = _db.syncDao;
    final device = await dao.existingDeviceId() ?? newUuid7(now: _clock.now());
    await dao.ensureState(device, accountId);
    await dao.setStatus(device, 'syncing');
    var pushed = 0, pulled = 0;
    try {
      pushed = await _push(device);
      pulled = await _pull(device);
      await dao.setStatus(device, 'idle', at: _clock.now());
      return SyncOutcome(pushed: pushed, pulled: pulled);
    } on AppError catch (e) {
      await dao.setStatus(device, 'error');
      return SyncOutcome(error: e, pushed: pushed, pulled: pulled);
    }
  }

  Future<int> _push(String device) async {
    final dao = _db.syncDao;
    var total = 0;
    while (true) {
      final batch = await dao.due(_clock.now());
      if (batch.isEmpty) return total;
      final Map<String, dynamic> data;
      try {
        data = await _api.post('/sync/push', {
          'device_id': device,
          'protocol_version': 1,
          'cursor': await dao.cursorFor(device),
          'mutations': [for (final m in batch) _wire(m)],
        }) as Map<String, dynamic>;
      } on AppError catch (e) {
        if (_retryable(e)) {
          final next = _clock.now().add(
            retryDelay(batch.first.attemptCount + 1, random: _random),
          );
          await dao.markAttemptFailed(batch, e.code.wire, next);
        }
        rethrow;
      }
      final results = {
        for (final r in (data['results'] as List).cast<Map<String, dynamic>>())
          r['mutation_id'] as String: r,
      };
      var handled = 0;
      for (final m in batch) {
        final r = results[m.mutationId];
        if (r == null) continue;
        await dao.applyPushResult(m, r, _clock.now());
        handled++;
      }
      total += handled;
      if (handled == 0) {
        return total; // server returned nothing usable: stop, no loop
      }
    }
  }

  Future<int> _pull(String device) async {
    final dao = _db.syncDao;
    var total = 0;
    while (true) {
      final cursor = await dao.cursorFor(device);
      final data = await _api.get(
        '/sync/pull',
        query: {'cursor': '$cursor'},
      ) as Map<String, dynamic>;
      final changes = (data['changes'] as List).cast<Map<String, dynamic>>();
      await dao.applyPulledPage(
        deviceId: device,
        changes: changes,
        nextCursor: data['next_cursor'] as int,
        now: _clock.now(),
      );
      total += changes.length;
      if (data['has_more'] != true) return total;
    }
  }

  static bool _retryable(AppError e) =>
      e.retryable ||
      e.code == ErrorCode.dependencyUnavailable ||
      e.code == ErrorCode.rateLimited ||
      e.code == ErrorCode.internalError;

  static Map<String, dynamic> _wire(OutboxMutation m) => {
    'mutation_id': m.mutationId,
    'workspace_id': m.workspaceId,
    'entity_type': m.entityType,
    'entity_id': m.entityId,
    'operation': m.operation,
    'base_version': m.baseVersion,
    'changes': jsonDecode(m.payload),
  };
}
