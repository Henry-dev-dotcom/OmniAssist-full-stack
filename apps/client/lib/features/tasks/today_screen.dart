import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../database/app_database.dart';
import '../../shared_widgets/async_state_view.dart';
import '../auth/auth_controller.dart';
import 'task_widgets.dart';

final _todayProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  final ws = ref.watch(authControllerProvider).value?.workspaceId;
  return ws == null
      ? const Stream.empty()
      : ref.watch(tasksRepositoryProvider).watchToday(ws);
});

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(_todayProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Today')),
      floatingActionButton: const QuickCaptureButton(),
      body: today.when(
        loading: () => const LoadingView(),
        error: (_, _) => const EmptyStateView(
            title: 'Cannot load Today',
            message: 'Restart the app. Your data is safe.'),
        data: (rows) => rows.isEmpty
            ? const EmptyStateView(
                title: 'Nothing due',
                message: 'Tasks due today or overdue show up here.')
            : ListView(children: [for (final t in rows) TaskTile(task: t)]),
      ),
    );
  }
}
