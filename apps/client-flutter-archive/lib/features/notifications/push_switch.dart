import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors/app_error.dart';
import 'web_push.dart';

final _pushOnProvider = FutureProvider.autoDispose<bool>(
  (_) async => await currentPushEndpoint() != null,
);

/// Turns reminder notifications on for this device (decision 0006). The browser asks
/// for permission only after this tap, never on page load.
class PushSwitch extends ConsumerStatefulWidget {
  const PushSwitch({super.key});
  @override
  ConsumerState<PushSwitch> createState() => _PushSwitchState();
}

class _PushSwitchState extends ConsumerState<PushSwitch> {
  bool _busy = false;

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _set(bool on) async {
    final api = ref.read(apiClientProvider);
    setState(() => _busy = true);
    try {
      if (on) {
        final key =
            (await api.get('/push/public-key')
                    as Map<String, dynamic>)['public_key']
                as String;
        final sub = await subscribePush(key);
        if (sub == null) {
          _say(
            'Notifications are blocked. Allow them in the browser settings.',
          );
          return;
        }
        await api.post('/push/subscriptions', sub);
        _say('Reminders will now appear on this device.');
      } else {
        final endpoint = await unsubscribePush();
        if (endpoint != null) {
          await api.post('/push/subscriptions/remove', {'endpoint': endpoint});
        }
      }
    } on AppError catch (e) {
      _say(e.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(_pushOnProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!pushSupported) {
      return const ListTile(
        leading: Icon(Icons.notifications_off_outlined),
        title: Text('Reminder notifications'),
        subtitle: Text(
          'Not available in this browser. On iPhone, add OmniAssist to the Home '
          'Screen first. Reminders still appear in the notification center.',
        ),
      );
    }
    final on = ref.watch(_pushOnProvider).value ?? false;
    return SwitchListTile(
      secondary: const Icon(Icons.notifications_active_outlined),
      title: const Text('Reminder notifications on this device'),
      subtitle: Text(
        pushPermission == 'denied'
            ? 'Blocked in the browser settings'
            : 'Even when the app is closed',
      ),
      value: on,
      onChanged: _busy ? null : _set,
    );
  }
}
