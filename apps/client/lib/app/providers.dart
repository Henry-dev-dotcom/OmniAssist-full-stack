import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../core/net/api_client.dart';
import '../core/time/app_clock.dart';
import '../database/app_database.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/auth_repository.dart';
import '../features/auth/token_store.dart';
import '../features/notifications/notification_gateway.dart';
import '../features/notifications/notification_repository.dart';
import '../features/notifications/server_reminders.dart';
import '../features/projects/projects_repository.dart';
import '../features/tasks/tasks_repository.dart';
import '../features/time_blocks/time_blocks_repository.dart';
import '../sync/sync_engine.dart';
import 'router.dart';

final clockProvider = Provider<AppClock>((_) => const SystemClock());

const _apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000/api/v1',
);

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final tokenStoreProvider = Provider<TokenStore>((_) => SecureTokenStore());

final apiClientProvider = Provider<ApiClient>(
  (_) => ApiClient(baseUrl: _apiBase, client: http.Client()),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStoreProvider),
  ),
);

final projectsRepositoryProvider = Provider<ProjectsRepository>(
  (ref) =>
      ProjectsRepository(ref.watch(databaseProvider), ref.watch(clockProvider)),
);

/// Swap this override once a platform notification plugin is chosen.
final notificationGatewayProvider = Provider<NotificationGateway>(
  (_) => const NoopGateway(),
);

final serverRemindersProvider = Provider<ServerReminders>(
  (ref) => ServerReminders(
    ref.watch(databaseProvider),
    ref.watch(apiClientProvider),
  ),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
    ref.watch(notificationGatewayProvider),
    ref.watch(serverRemindersProvider),
  ),
);

final tasksRepositoryProvider = Provider<TasksRepository>(
  (ref) => TasksRepository(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
    ref.watch(notificationRepositoryProvider),
  ),
);

final timeBlocksRepositoryProvider = Provider<TimeBlocksRepository>(
  (ref) => TimeBlocksRepository(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
  ),
);

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => SyncEngine(
    ref.watch(databaseProvider),
    ref.watch(apiClientProvider),
    ref.watch(clockProvider),
  ),
);

/// Re-evaluates the router redirect when auth state changes.
final routerProvider = Provider<GoRouter>((ref) {
  final signedIn = ValueNotifier<bool?>(null);
  ref.listen(authControllerProvider, (_, next) {
    signedIn.value = next.isLoading ? null : next.value != null;
  }, fireImmediately: true);
  ref.onDispose(signedIn.dispose);
  return buildRouter(signedIn: signedIn);
});
