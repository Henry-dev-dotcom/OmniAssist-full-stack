import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/router.dart';
import '../features/sync/sync_status.dart';
import '../features/tasks/task_widgets.dart';

class NavDestination {
  const NavDestination(this.label, this.icon, this.path);
  final String label;
  final IconData icon;
  final String path;
}

const _desktopBreakpoint = 900.0;

/// Desktop keyboard paths (Spec 8.2): no printable keys, so typing never triggers them.
const keyboardShortcuts = <(String, String)>[
  ('Ctrl + K', 'Search'),
  ('Alt + N', 'Quick capture to the Inbox'),
  ('Alt + 1 … 5', 'Today, Calendar, Projects, Inbox, More'),
  ('Space', 'Toggle the focused checkbox, e.g. complete a task'),
];

/// Sidebar rail on wide screens, bottom bar on narrow ones.
class AppScaffold extends ConsumerWidget {
  const AppScaffold({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  int get _index {
    final i = navDestinations.indexWhere((d) => location.startsWith(d.path));
    return i < 0 ? 0 : i;
  }

  void _go(BuildContext context, int i) => context.go(navDestinations[i].path);

  @override
  Widget build(BuildContext context, WidgetRef ref) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
          context.push('/app/search'),
      const SingleActivator(LogicalKeyboardKey.keyN, alt: true): () =>
          captureTask(context, ref),
      for (final (i, key) in const [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
      ].indexed)
        SingleActivator(key, alt: true): () => _go(context, i),
    },
    child: Focus(autofocus: true, child: _layout(context)),
  );

  Widget _layout(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            Semantics(
              container: true,
              label: 'Primary navigation',
              child: NavigationRail(
                selectedIndex: _index,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (i) => _go(context, i),
                destinations: [
                  for (final d in navDestinations)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      label: Text(d.label),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  const SyncBanner(),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SyncBanner(),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => _go(context, i),
        destinations: [
          for (final d in navDestinations)
            NavigationDestination(icon: Icon(d.icon), label: d.label),
        ],
      ),
    );
  }
}
