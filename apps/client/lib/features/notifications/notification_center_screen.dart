import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/providers.dart';
import '../../database/app_database.dart';
import '../../shared_widgets/async_state_view.dart';
import '../auth/auth_controller.dart';
import '../time_blocks/calendar_math.dart';
import 'notification_repository.dart';
import 'reminder_rules.dart';

final _unreadOnlyProvider = StateProvider.autoDispose<bool>((_) => false);

final _centerProvider = StreamProvider.autoDispose<List<Reminder>>((ref) {
  final ws = ref.watch(authControllerProvider).value?.workspaceId;
  if (ws == null) return const Stream.empty();
  return ref
      .watch(notificationRepositoryProvider)
      .watchCenter(ws, unreadOnly: ref.watch(_unreadOnlyProvider));
});

final _osPermittedProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(notificationRepositoryProvider).osPermitted(),
);

/// Unread count for a badge on the navigation bar.
final unreadCountProvider = StreamProvider.autoDispose<int>((ref) {
  final ws = ref.watch(authControllerProvider).value?.workspaceId;
  return ws == null
      ? Stream.value(0)
      : ref.watch(notificationRepositoryProvider).watchUnread(ws);
});

/// Fires due reminders while the app is open. Watch it once near the app root.
final reminderTickerProvider = Provider<void>((ref) {
  final repo = ref.watch(notificationRepositoryProvider);
  repo.deliverDue();
  final timer = Timer.periodic(
    const Duration(seconds: 30),
    (_) => repo.deliverDue(),
  );
  ref.onDispose(timer.cancel);
});

class NotificationCenterScreen extends ConsumerWidget {
  const NotificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(_centerProvider);
    final unreadOnly = ref.watch(_unreadOnlyProvider);
    final permitted = ref.watch(_osPermittedProvider).value ?? true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Quiet hours',
            icon: const Icon(Icons.bedtime_outlined),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const _QuietHoursSheet(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!permitted)
            const MaterialBanner(
              leading: Icon(Icons.notifications_off_outlined),
              content: Text(
                'System notifications are off. Reminders still show here.',
              ),
              actions: [SizedBox.shrink()],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: !unreadOnly,
                  onSelected: (_) =>
                      ref.read(_unreadOnlyProvider.notifier).state = false,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Unread'),
                  selected: unreadOnly,
                  onSelected: (_) =>
                      ref.read(_unreadOnlyProvider.notifier).state = true,
                ),
              ],
            ),
          ),
          Expanded(
            child: rows.when(
              loading: () => const LoadingView(),
              error: (_, _) => const EmptyStateView(
                title: 'Cannot load notifications',
                message: 'Restart the app. Your data is safe.',
              ),
              data: (list) => list.isEmpty
                  ? EmptyStateView(
                      title: unreadOnly
                          ? 'All caught up'
                          : 'No notifications yet',
                      message: 'Reminders you set on tasks show up here.',
                    )
                  : ListView(children: [for (final r in list) _Row(r)]),
            ),
          ),
        ],
      ),
    );
  }
}

String statusLabel(Reminder r) => switch (r.status) {
  'sent' => 'Due',
  'snoozed' => 'Snoozed until ${hhmm(r.snoozedUntil ?? r.remindAt)}',
  'failed' => 'Could not deliver',
  'dismissed' => 'Dismissed',
  'acted_on' => 'Done',
  _ => r.status,
};

class _Row extends ConsumerWidget {
  const _Row(this.r);
  final Reminder r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(notificationRepositoryProvider);
    final unread =
        r.readAt == null && (r.status == 'sent' || r.status == 'failed');
    final canAct =
        r.status == 'sent' || r.status == 'snoozed' || r.status == 'failed';
    return ListTile(
      leading: Icon(
        r.urgency == 'critical'
            ? Icons.priority_high
            : Icons.notifications_outlined,
      ),
      title: Text(
        r.title,
        style: TextStyle(
          fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: Text('${statusLabel(r)} · ${offsetLabel(r.offsetSpec)}'),
      onTap: unread ? () => repo.markRead(r.id) : null,
      trailing: !canAct
          ? null
          : PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (v) => switch (v) {
                'snooze' => repo.snooze(r.id, minutes: 10),
                'hour' => repo.snooze(r.id, minutes: 60),
                'done' => repo.acknowledge(r.id),
                _ => repo.dismiss(r.id),
              },
              itemBuilder: (_) => [
                if (r.status != 'failed') ...const [
                  PopupMenuItem(value: 'done', child: Text('Mark done')),
                  PopupMenuItem(value: 'snooze', child: Text('Snooze 10 min')),
                  PopupMenuItem(value: 'hour', child: Text('Snooze 1 hour')),
                ],
                const PopupMenuItem(value: 'dismiss', child: Text('Dismiss')),
              ],
            ),
    );
  }
}

class _QuietHoursSheet extends ConsumerStatefulWidget {
  const _QuietHoursSheet();
  @override
  ConsumerState<_QuietHoursSheet> createState() => _QuietHoursSheetState();
}

class _QuietHoursSheetState extends ConsumerState<_QuietHoursSheet> {
  QuietHours? _q = defaultQuiet;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    ref.read(notificationRepositoryProvider).quietHours().then((q) {
      if (mounted) {
        setState(() {
          _q = q;
          _loaded = true;
        });
      }
    });
  }

  Future<void> _pick(bool start) async {
    final q = _q ?? defaultQuiet;
    final m = start ? q.startMinutes : q.endMinutes;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (t == null) return;
    final v = t.hour * 60 + t.minute;
    final next = start
        ? QuietHours(v, q.endMinutes)
        : QuietHours(q.startMinutes, v);
    setState(() => _q = next);
    await ref.read(notificationRepositoryProvider).setQuietHours(next);
  }

  String _fmt(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final q = _q;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quiet hours', style: Theme.of(context).textTheme.titleLarge),
          const Text(
            'Reminders wait until quiet hours end. Critical reminders still fire.',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use quiet hours'),
            value: q != null,
            onChanged: !_loaded
                ? null
                : (on) async {
                    final next = on ? defaultQuiet : null;
                    setState(() => _q = next);
                    await ref
                        .read(notificationRepositoryProvider)
                        .setQuietHours(next);
                  },
          ),
          if (q != null) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('From'),
              trailing: Text(_fmt(q.startMinutes)),
              onTap: () => _pick(true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Until'),
              trailing: Text(_fmt(q.endMinutes)),
              onTap: () => _pick(false),
            ),
          ],
        ],
      ),
    );
  }
}
