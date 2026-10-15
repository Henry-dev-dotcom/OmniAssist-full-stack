import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/notifications/notification_center_screen.dart';
import '../features/sync/sync_controller.dart';
import 'providers.dart';
import 'theme.dart';

class OmniAssistApp extends ConsumerWidget {
  const OmniAssistApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(syncControllerProvider); // keeps background sync alive
    ref.watch(reminderTickerProvider); // fires due reminders while open
    return MaterialApp.router(
        title: 'OmniAssist',
        theme: buildTheme(),
        routerConfig: ref.watch(routerProvider),
      );
  }
}
