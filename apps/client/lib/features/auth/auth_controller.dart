import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors/app_error.dart';
import '../../core/result/result.dart';
import '../notifications/web_push.dart';
import 'auth_repository.dart';

/// null = signed out, Session = signed in. Loading while restoring at start-up.
class AuthController extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() async {
    final r = await ref.read(authRepositoryProvider).restore();
    return switch (r) {
      Ok(:final value) => value,
      Err() => null, // not signed in, or offline: sign-in screen decides
    };
  }

  /// Returns an error to show, or null on success.
  Future<AppError?> signIn(String email, String password) =>
      _adopt(ref.read(authRepositoryProvider).signIn(email, password));

  Future<AppError?> register(String email, String password, String name) =>
      _adopt(ref.read(authRepositoryProvider).register(email, password, name));

  Future<AppError?> _adopt(Future<Result<Session>> attempt) async {
    final r = await attempt;
    switch (r) {
      case Ok(:final value):
        state = AsyncData(value);
        return null;
      case Err(:final error):
        return error;
    }
  }

  /// [removeLocalData] also clears this device, including unsent changes.
  Future<void> signOut({bool removeLocalData = false}) async {
    // Stop this device getting the account's reminders before the tokens go.
    try {
      final endpoint = await unsubscribePush();
      if (endpoint != null) {
        await ref.read(apiClientProvider).post('/push/subscriptions/remove', {
          'endpoint': endpoint,
        });
      }
    } on Object {
      // Offline: the browser subscription is already gone, so nothing is delivered here.
    }
    await ref.read(authRepositoryProvider).signOut();
    if (removeLocalData) await ref.read(databaseProvider).wipe();
    state = const AsyncData(null);
  }

  /// Deletes the account on the server, then everything on this device.
  Future<AppError?> deleteAccount() async {
    try {
      await ref
          .read(apiClientProvider)
          .delete('/me', body: const {'confirm': 'DELETE'});
    } on AppError catch (e) {
      return e;
    }
    await ref.read(authRepositoryProvider).forget();
    await ref.read(databaseProvider).wipe();
    state = const AsyncData(null);
    return null;
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, Session?>(
  AuthController.new,
);
