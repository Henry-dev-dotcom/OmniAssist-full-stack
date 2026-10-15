import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/sign_in_screen.dart';
import '../features/notifications/notification_center_screen.dart';
import '../features/projects/projects_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sync/sync_center_screen.dart';
import '../features/tasks/inbox_screen.dart';
import '../features/tasks/task_detail_screen.dart';
import '../features/time_blocks/calendar_screen.dart';
import '../features/today/today_page.dart';
import '../shared_widgets/app_scaffold.dart';
import '../shared_widgets/async_state_view.dart';

/// Primary navigation. Mobile shows the first four plus More (settings).
const navDestinations = <NavDestination>[
  NavDestination('Today', Icons.today_outlined, '/app/today'),
  NavDestination('Calendar', Icons.calendar_month_outlined, '/app/calendar'),
  NavDestination('Projects', Icons.folder_outlined, '/app/projects'),
  NavDestination('Inbox', Icons.inbox_outlined, '/app/inbox'),
  NavDestination('More', Icons.more_horiz, '/app/settings'),
];

GoRoute _placeholder(String path, String title) => GoRoute(
  path: path,
  builder: (_, _) =>
      EmptyStateView(title: title, message: 'Coming in a later task.'),
);

/// [signedIn]: null while restoring (no redirect), false = go to sign-in.
/// When omitted (tests, previews) the router never redirects.
GoRouter buildRouter({
  String initialLocation = '/app/today',
  ValueListenable<bool?>? signedIn,
}) => GoRouter(
  initialLocation: initialLocation,
  refreshListenable: signedIn,
  redirect: (_, state) {
    final ok = signedIn?.value;
    if (ok == null) return null;
    final onAuth = state.uri.path == '/sign-in';
    if (!ok && !onAuth) return '/sign-in';
    if (ok && onAuth) return '/app/today';
    return null;
  },
  routes: [
    // Auth group. Onboarding arrives with a later task.
    GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
    _placeholder('/onboarding', 'Onboarding'),
    ShellRoute(
      builder: (_, state, child) =>
          AppScaffold(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/app/today', builder: (_, _) => const TodayPage()),
        GoRoute(
          path: '/app/calendar',
          builder: (_, _) => const CalendarScreen(),
        ),
        GoRoute(
          path: '/app/tasks/:id',
          builder: (_, state) =>
              TaskDetailScreen(taskId: state.pathParameters['id']!),
        ),
        GoRoute(path: '/app/inbox', builder: (_, _) => const InboxScreen()),
        GoRoute(
          path: '/app/projects',
          builder: (_, _) => const ProjectsScreen(),
        ),
        _placeholder('/app/search', 'Search'),
        GoRoute(
          path: '/app/notifications',
          builder: (_, _) => const NotificationCenterScreen(),
        ),
        GoRoute(path: '/app/sync', builder: (_, _) => const SyncCenterScreen()),
        GoRoute(
          path: '/app/settings',
          builder: (_, _) => const SettingsScreen(),
        ),
      ],
    ),
  ],
);
