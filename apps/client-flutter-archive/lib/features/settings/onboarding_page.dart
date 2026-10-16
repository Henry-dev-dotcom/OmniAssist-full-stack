import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/errors/app_error.dart';
import '../../core/errors/error_codes.dart';
import '../../shared_widgets/async_state_view.dart';

/// Common IANA zones; any other valid zone can be typed (the server checks it).
const _zones = [
  'UTC',
  'Africa/Accra',
  'Africa/Lagos',
  'Africa/Nairobi',
  'Africa/Johannesburg',
  'Europe/London',
  'Europe/Berlin',
  'America/New_York',
  'America/Chicago',
  'America/Los_Angeles',
  'Asia/Kolkata',
  'Asia/Shanghai',
  'Asia/Tokyo',
  'Australia/Sydney',
];

final _meProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async =>
      await ref.read(apiClientProvider).get('/me') as Map<String, dynamic>,
);

/// S03: time zone, work hours and reminder preferences. Every step is optional
/// (Spec 4.2); the same screen edits them later from Settings.
class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(_meProvider)
      .when(
        loading: () => const Scaffold(body: LoadingView()),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Profile')),
          body: EmptyStateView(
            title: 'Needs a connection',
            message:
                '${e is AppError ? e.message : 'Cannot load your profile.'} '
                'Your planner works offline; set this up later in Settings.',
            actionLabel: 'Continue to Today',
            onAction: () => context.go('/app/today'),
          ),
        ),
        data: (me) => _Form(me: me),
      );
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.me});
  final Map<String, dynamic> me;
  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final Map<String, dynamic> _prefs = Map.of(
    (widget.me['preferences'] as Map<String, dynamic>?) ?? const {},
  );
  late final _name = TextEditingController(
    text: widget.me['display_name'] as String? ?? '',
  );
  late final _zone = TextEditingController(
    text: widget.me['timezone'] as String? ?? 'UTC',
  );
  late TimeOfDay _workStart = _time(_prefs['work_hours']?['start'], 9);
  late TimeOfDay _workEnd = _time(_prefs['work_hours']?['end'], 17);
  late bool _quiet = _prefs['quiet_hours'] != null;
  late TimeOfDay _quietStart = _time(_prefs['quiet_hours']?['start'], 22);
  late TimeOfDay _quietEnd = _time(_prefs['quiet_hours']?['end'], 7);
  late String _reminder = (_prefs['default_reminder'] as String?) ?? 'at_due';
  String? _error;
  bool _busy = false;

  static TimeOfDay _time(Object? hhmm, int fallback) {
    final parts = '${hhmm ?? ''}'.split(':');
    final h = int.tryParse(parts.first),
        m = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    return h == null || m == null
        ? TimeOfDay(hour: fallback, minute: 0)
        : TimeOfDay(hour: h, minute: m);
  }

  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _name.dispose();
    _zone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter your name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final prefs = {
      ..._prefs,
      'work_hours': {'start': _hhmm(_workStart), 'end': _hhmm(_workEnd)},
      'default_reminder': _reminder,
      'quiet_hours': _quiet
          ? {'start': _hhmm(_quietStart), 'end': _hhmm(_quietEnd)}
          : null,
    }..removeWhere((_, v) => v == null);
    try {
      await ref.read(apiClientProvider).patch('/me', {
        'display_name': _name.text.trim(),
        'timezone': _zone.text.trim(),
        'preferences': prefs,
      });
      if (mounted) context.go('/app/today');
    } on AppError catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.code == ErrorCode.validationError
              ? 'Check the time zone: use a name like Africa/Accra.'
              : e.message;
        });
      }
    }
  }

  Widget _timeRow(String label, TimeOfDay value, ValueChanged<TimeOfDay> set) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        trailing: OutlinedButton(
          onPressed: () async {
            final t = await showTimePicker(
              context: context,
              initialTime: value,
            );
            if (t != null) setState(() => set(t));
          },
          child: Text(value.format(context)),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Set up your planner'),
      actions: [
        TextButton(
          onPressed: () => context.go('/app/today'),
          child: const Text('Skip for now'),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'These help reminders and Today fit your day. You can change them any '
              'time in Settings.',
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            TextField(
              controller: _name,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _zone.text),
              optionsBuilder: (v) => _zones.where(
                (z) => z.toLowerCase().contains(v.text.toLowerCase()),
              ),
              onSelected: (z) => _zone.text = z,
              fieldViewBuilder: (context, controller, focus, submit) {
                controller.addListener(() => _zone.text = controller.text);
                return TextField(
                  controller: controller,
                  focusNode: focus,
                  decoration: const InputDecoration(
                    labelText: 'Time zone',
                    helperText: 'For example Africa/Accra or Europe/London',
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Text('Work hours', style: Theme.of(context).textTheme.titleSmall),
            _timeRow('Start', _workStart, (t) => _workStart = t),
            _timeRow('End', _workEnd, (t) => _workEnd = t),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _reminder,
              decoration: const InputDecoration(labelText: 'Default reminder'),
              items: const [
                DropdownMenuItem(value: 'at_due', child: Text('When due')),
                DropdownMenuItem(
                  value: '15m',
                  child: Text('15 minutes before'),
                ),
                DropdownMenuItem(value: '1h', child: Text('1 hour before')),
                DropdownMenuItem(value: '1d', child: Text('1 day before')),
              ],
              onChanged: (v) => setState(() => _reminder = v ?? _reminder),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Quiet hours'),
              subtitle: const Text('Only critical reminders interrupt'),
              value: _quiet,
              onChanged: (v) => setState(() => _quiet = v),
            ),
            if (_quiet) ...[
              _timeRow('From', _quietStart, (t) => _quietStart = t),
              _timeRow('Until', _quietEnd, (t) => _quietEnd = t),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ),
  );
}
