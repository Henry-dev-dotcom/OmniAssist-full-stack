import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors/app_error.dart';
import '../auth/auth_controller.dart';

enum SyncPhase { idle, syncing, failed }

class SyncUiState {
  const SyncUiState({this.phase = SyncPhase.idle, this.error, this.lastSyncAt});
  final SyncPhase phase;
  final AppError? error;
  final DateTime? lastSyncAt;
}

/// Syncs after sign-in, on demand, and every minute while signed in.
class SyncController extends Notifier<SyncUiState> {
  Timer? _timer;

  @override
  SyncUiState build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen(authControllerProvider, (_, next) {
      _timer?.cancel();
      if (next.value != null) {
        syncNow();
        _timer = Timer.periodic(const Duration(minutes: 1), (_) => syncNow());
      }
    }, fireImmediately: true);
    return const SyncUiState();
  }

  Future<void> syncNow() async {
    final account = ref.read(authControllerProvider).value?.userId;
    if (account == null || state.phase == SyncPhase.syncing) return;
    state = SyncUiState(phase: SyncPhase.syncing, lastSyncAt: state.lastSyncAt);
    final out = await ref.read(syncEngineProvider).syncOnce(account);
    state = out.ok
        ? SyncUiState(lastSyncAt: ref.read(clockProvider).now())
        : SyncUiState(
            phase: SyncPhase.failed,
            error: out.error,
            lastSyncAt: state.lastSyncAt,
          );
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncUiState>(
  SyncController.new,
);
