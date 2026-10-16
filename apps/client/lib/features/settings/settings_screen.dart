import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/errors/app_error.dart';
import '../../core/errors/error_codes.dart';
import '../../shared_widgets/app_scaffold.dart';
import '../../shared_widgets/file_io.dart';
import '../auth/auth_controller.dart';
import '../sync/sync_status.dart';

/// S24: account, export and deletion.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('Profile and working hours'),
          subtitle: const Text('Name, time zone, work hours, reminders'),
          onTap: () => context.push('/onboarding'),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Notifications'),
          subtitle: const Text('Reminders, quiet hours'),
          onTap: () => context.go('/app/notifications'),
        ),
        ListTile(
          leading: const Icon(Icons.search),
          title: const Text('Search'),
          onTap: () => context.go('/app/search'),
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Sync Center'),
          subtitle: const Text('Sync state, errors and conflicts'),
          onTap: () => context.go('/app/sync'),
        ),
        ListTile(
          leading: const Icon(Icons.keyboard_outlined),
          title: const Text('Keyboard shortcuts'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Keyboard shortcuts'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (keys, what) in keyboardShortcuts)
                    ListTile(
                      dense: true,
                      title: Text(what),
                      trailing: Text(keys),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Export my data'),
          subtitle: const Text('Everything in this workspace, as JSON or CSV'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => const _ExportDialog(),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.password),
          title: const Text('Change password'),
          subtitle: const Text('Other devices will need to sign in again'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => const _PasswordDialog(),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => _signOut(context, ref),
        ),
        ListTile(
          leading: Icon(
            Icons.delete_forever_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            'Delete account',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          subtitle: const Text('Removes your account and all its data'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => const _DeleteAccountDialog(),
          ),
        ),
      ],
    ),
  );

  /// Spec 4.1: explain what happens to unsent changes before signing out.
  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final pending = await ref.read(pendingCountProvider.future);
    if (!context.mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          pending == 0
              ? 'Everything is synced. You can keep a copy on this device or remove it.'
              : '$pending changes have not reached the server yet. If you keep them, '
                    'they upload when you sign back in to this account; they are never '
                    'sent to another account. Removing the data deletes them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'remove'),
            child: const Text('Sign out and remove data'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'keep'),
            child: const Text('Sign out, keep data'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await ref
        .read(authControllerProvider.notifier)
        .signOut(removeLocalData: choice == 'remove');
  }
}

class _ExportDialog extends ConsumerStatefulWidget {
  const _ExportDialog();
  @override
  ConsumerState<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<_ExportDialog> {
  String _format = 'json';
  String? _status;
  bool _busy = false;

  /// Starts a server export job, waits for it, then saves the file.
  Future<void> _run() async {
    final ws = ref.read(authControllerProvider).value?.workspaceId;
    if (ws == null) return;
    final api = ref.read(apiClientProvider);
    setState(() {
      _busy = true;
      _status = 'Preparing your export…';
    });
    try {
      final job = await api.post('/exports', {
        'workspace_id': ws,
        'format': _format,
      }) as Map<String, dynamic>;
      Map<String, dynamic> state = job;
      for (var i = 0; i < 30 && state['status'] == 'pending'; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        state = await api.get('/exports/${job['id']}') as Map<String, dynamic>;
      }
      if (state['status'] != 'ready') {
        throw AppError(
          code: ErrorCode.dependencyUnavailable,
          message: state['status'] == 'pending'
              ? 'The export is taking long. Try again in a minute.'
              : 'The export failed. Try again.',
          retryable: true,
        );
      }
      final bytes = await api.getBytes(state['download_url'] as String);
      final json = _format == 'json';
      await saveBytesFile(
        'omniassist-export.${json ? 'json' : 'zip'}',
        bytes,
        json ? 'application/json' : 'application/zip',
      );
      if (mounted) setState(() => _status = 'Saved.');
    } on AppError catch (e) {
      if (mounted) setState(() => _status = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Export my data'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Includes active, archived and deleted records with their IDs, links and '
          'sync details. Needs a connection; the download link expires after an hour.',
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'json', label: Text('JSON')),
            ButtonSegment(value: 'csv', label: Text('CSV (ZIP)')),
          ],
          selected: {_format},
          onSelectionChanged: _busy
              ? null
              : (s) => setState(() => _format = s.first),
        ),
        if (_status != null) ...[
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(_status!)),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton(onPressed: _busy ? null : _run, child: const Text('Export')),
    ],
  );
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();
  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref.read(authControllerProvider.notifier).deleteAccount();
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err.message;
      });
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _confirm.text.trim() == 'DELETE' && !_busy;
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently deletes your account, every workspace you own and all '
            'their projects, tasks, reviews, analyses and experiments, and signs you '
            'out everywhere. Export your data first if you want a copy. '
            'Copies in server backups expire with the backup retention period.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Type DELETE to confirm',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: ready ? _delete : null,
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}

class _PasswordDialog extends ConsumerStatefulWidget {
  const _PasswordDialog();
  @override
  ConsumerState<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends ConsumerState<_PasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = _current.text.isEmpty
        ? 'Enter your current password.'
        : _next.text.length < 8
        ? 'Use a new password with at least 8 characters.'
        : _next.text != _again.text
        ? 'The new passwords do not match.'
        : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref
        .read(authRepositoryProvider)
        .changePassword(_current.text, _next.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err.message;
      });
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Password changed')));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change password'),
    content: AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          TextField(
            controller: _current,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Current password'),
          ),
          TextField(
            controller: _next,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(labelText: 'New password'),
          ),
          TextField(
            controller: _again,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(labelText: 'New password again'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: const Text('Change'),
      ),
    ],
  );
}
