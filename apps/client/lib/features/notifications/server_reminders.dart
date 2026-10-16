import 'dart:convert';

import '../../core/errors/app_error.dart';
import '../../core/net/api_client.dart';
import '../../database/app_database.dart';

const _pendingKey = 'server_reminders.pending';

/// Mirrors a task's reminders to the server, which sends them as push notifications
/// (decision 0006). The device stays the source of truth: when the server cannot take
/// them yet (offline, or the task has not synced), the task waits in a persisted list
/// and is sent again after the next successful sync.
class ServerReminders {
  ServerReminders(this._db, this._api);
  final AppDatabase _db;
  final ApiClient _api;

  Future<void> mirror(String taskId) async {
    if (!await _send(taskId)) await _setPending({...await _pending(), taskId});
  }

  /// Retries every waiting task; call after a successful sync.
  Future<void> flush() async {
    final waiting = await _pending();
    if (waiting.isEmpty) return;
    final left = <String>{};
    for (final id in waiting) {
      if (!await _send(id)) left.add(id);
    }
    await _setPending(left);
  }

  Future<bool> _send(String taskId) async {
    final open = [
      for (final r in await _db.reminderDao.forTask(taskId, openOnly: true))
        if (r.status == 'scheduled') r,
    ];
    try {
      await _api.put('/tasks/$taskId/reminders', {
        'offsets': [for (final r in open) r.offsetSpec],
        'urgency': open.isEmpty ? 'normal' : open.first.urgency,
        'channel': 'push',
      });
      return true;
    } on AppError {
      return false;
    }
  }

  Future<Set<String>> _pending() async {
    final raw = await _db.reminderDao.setting(_pendingKey);
    return raw == null
        ? <String>{}
        : {for (final id in jsonDecode(raw) as List<dynamic>) '$id'};
  }

  Future<void> _setPending(Set<String> ids) =>
      _db.reminderDao.putSetting(_pendingKey, jsonEncode(ids.toList()));
}
