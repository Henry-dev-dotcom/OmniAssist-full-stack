import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/sign_in_screen.dart';
import '../features/notifications/notification_center_screen.dart';
import '../features/projects/projects_screen.dart';
import '../features/settings/onboarding_page.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/workspaces_page.dart';
import '../features/sync/conflict_page.dart';
import '../features/sync/sync_center_screen.dart';
import '../features/tasks/inbox_screen.dart';
import '../features/tasks/task_detail_screen.dart';
import '../features/time_blocks/calendar_screen.dart';
import '../features/search/search_page.dart';
import '../features/today/today_page.dart';
import '../features/analyses/analysis_page.dart';
import '../features/experiments/experiment_page.dart';
import '../features/milestones/milestone_page.dart';
import '../features/projects/project_page.dart';
import '../features/reviews/review_board_page.dart';
import '../features/reviews/review_item_page.dart';
import '../shared_widgets/app_scaffold.dart';

/// Primary navigation. Mobile shows the first four plus More (settings).
const navDestinations = <NavDestination>[
  NavDestination('Today', Icons.today_outlined, '/app/today'),
  NavDestination('Calendar', Icons.calendar_month_outlined, '/app/calendar'),
  NavDestination('Projects', Icons.folder_outlined, '/app/projects'),
  NavDestination('Inbox', Icons.inbox_outlined, '/app/inbox'),
  NavDestination('More', Icons.more_horiz, '/app/settings'),
];

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
    GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
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
        GoRoute(
          path: '/app/projects/:id',
          builder: (_, st) => ProjectPage(projectId: st.pathParameters['id']!),
        ),
        GoRoute(
          path: '/app/milestones/:id',
          builder: (_, st) =>
              MilestonePage(milestoneId: st.pathParameters['id']!),
        ),
        GoRoute(
          path: '/app/reviews/:id',
          builder: (_, st) =>
              ReviewBoardPage(reviewId: st.pathParameters['id']!),
        ),
        GoRoute(
          path: '/app/review-items/:id',
          builder: (_, st) => ReviewItemPage(itemId: st.pathParameters['id']!),
        ),
        GoRoute(
          path: '/app/analyses/:id',
          builder: (_, st) =>
              AnalysisPage(analysisId: st.pathParameters['id']!),
        ),
        GoRoute(
          path: '/app/experiments/:id',
          builder: (_, st) => ExperimentPage(entryId: st.pathParameters['id']!),
        ),
        GoRoute(
          path: '/app/sync/conflicts/:id',
          builder: (_, st) =>
              ConflictPage(conflictId: st.pathParameters['id']!),
        ),
        GoRoute(
          path: '/app/workspaces',
          builder: (_, _) => const WorkspacesPage(),
        ),
        GoRoute(path: '/app/inbox', builder: (_, _) => const InboxScreen()),
        GoRoute(
          path: '/app/projects',
          builder: (_, _) => const ProjectsScreen(),
        ),
        GoRoute(path: '/app/search', builder: (_, _) => const SearchPage()),
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
