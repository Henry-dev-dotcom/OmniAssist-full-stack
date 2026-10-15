import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors/app_error.dart';
import '../../database/app_database.dart';
import '../../shared_widgets/async_state_view.dart';
import '../auth/auth_controller.dart';
import 'calendar_math.dart';
import 'time_block_editor.dart';

enum CalendarView { day, agenda, week, month }

class _Range {
  const _Range(this.ws, this.start, this.end);
  final String ws;
  final DateTime start, end;
  @override
  bool operator ==(Object o) =>
      o is _Range && o.ws == ws && o.start == start && o.end == end;
  @override
  int get hashCode => Object.hash(ws, start, end);
}

final _blocksProvider = StreamProvider.autoDispose
    .family<List<TimeBlock>, _Range>(
      (ref, r) => ref
          .watch(timeBlocksRepositoryProvider)
          .watchRange(r.ws, r.start, r.end),
    );

final _unscheduledProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  final ws = ref.watch(authControllerProvider).value?.workspaceId;
  return ws == null
      ? const Stream.empty()
      : ref.watch(timeBlocksRepositoryProvider).watchUnscheduled(ws);
});

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  CalendarView _view = CalendarView.day;
  DateTime _day = dayOf(DateTime.now());

  (DateTime, DateTime) get _bounds => switch (_view) {
    CalendarView.day => (_day, addDays(_day, 1)),
    CalendarView.agenda => (_day, addDays(_day, 14)),
    CalendarView.week => (weekStart(_day), addDays(weekStart(_day), 7)),
    CalendarView.month => () {
      final cells = monthCells(_day);
      return (cells.first, addDays(cells.last, 1));
    }(),
  };

  void _step(int dir) => setState(() {
    _day = switch (_view) {
      CalendarView.day => addDays(_day, dir),
      CalendarView.agenda => addDays(_day, 14 * dir),
      CalendarView.week => addDays(_day, 7 * dir),
      CalendarView.month => DateTime(_day.year, _day.month + dir, 1),
    };
  });

  String get _title => switch (_view) {
    CalendarView.month => '${_months[_day.month - 1]} ${_day.year}',
    CalendarView.week =>
      'Week of ${_months[weekStart(_day).month - 1]} ${weekStart(_day).day}',
    _ => '${_months[_day.month - 1]} ${_day.day}, ${_day.year}',
  };

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(authControllerProvider).value?.workspaceId;
    final (start, end) = _bounds;
    final blocks = ws == null
        ? const AsyncValue<List<TimeBlock>>.data([])
        : ref.watch(_blocksProvider(_Range(ws, start.toUtc(), end.toUtc())));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            tooltip: 'Previous',
            onPressed: () => _step(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          TextButton(
            onPressed: () => setState(() => _day = dayOf(DateTime.now())),
            child: const Text('Today'),
          ),
          IconButton(
            tooltip: 'Next',
            onPressed: () => _step(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      floatingActionButton: ws == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showTimeBlockEditor(context, ws: ws, day: _day),
              icon: const Icon(Icons.add),
              label: const Text('Time block'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<CalendarView>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: CalendarView.day, label: Text('Day')),
                    ButtonSegment(
                      value: CalendarView.agenda,
                      label: Text('Agenda'),
                    ),
                    ButtonSegment(
                      value: CalendarView.week,
                      label: Text('Week'),
                    ),
                    ButtonSegment(
                      value: CalendarView.month,
                      label: Text('Month'),
                    ),
                  ],
                  selected: {_view},
                  onSelectionChanged: (s) => setState(() => _view = s.first),
                ),
                const SizedBox(height: 8),
                Text(_title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          Expanded(
            child: blocks.when(
              loading: () => const LoadingView(),
              error: (_, _) => const EmptyStateView(
                title: 'Cannot load Calendar',
                message: 'Restart the app. Your data is safe.',
              ),
              data: (rows) => ws == null
                  ? const EmptyStateView(
                      title: 'Not signed in',
                      message: 'Sign in to see your calendar.',
                    )
                  : switch (_view) {
                      CalendarView.day => _DayList(
                        day: _day,
                        blocks: blocksOnDay(rows, _day),
                        ws: ws,
                      ),
                      CalendarView.agenda => _Agenda(
                        from: _day,
                        blocks: rows,
                        ws: ws,
                      ),
                      CalendarView.week => _Week(
                        start: weekStart(_day),
                        blocks: rows,
                        onPick: (d) => setState(() {
                          _day = d;
                          _view = CalendarView.day;
                        }),
                      ),
                      CalendarView.month => _Month(
                        day: _day,
                        blocks: rows,
                        onPick: (d) => setState(() {
                          _day = d;
                          _view = CalendarView.day;
                        }),
                      ),
                    },
            ),
          ),
          if (ws != null) _Tray(ws: ws, day: _day),
        ],
      ),
    );
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class _DayList extends StatelessWidget {
  const _DayList({required this.day, required this.blocks, required this.ws});
  final DateTime day;
  final List<TimeBlock> blocks;
  final String ws;
  @override
  Widget build(BuildContext context) => blocks.isEmpty
      ? const EmptyStateView(
          title: 'Nothing scheduled',
          message: 'Add a time block, or pick a task from the tray below.',
        )
      : ListView(children: [for (final b in blocks) BlockTile(block: b)]);
}

class _Agenda extends StatelessWidget {
  const _Agenda({required this.from, required this.blocks, required this.ws});
  final DateTime from;
  final List<TimeBlock> blocks;
  final String ws;
  @override
  Widget build(BuildContext context) {
    final days = [for (var i = 0; i < 14; i++) addDays(from, i)]
        .where((d) => blocksOnDay(blocks, d).isNotEmpty)
        .toList();
    if (days.isEmpty) {
      return const EmptyStateView(
        title: 'Nothing in the next 14 days',
        message: 'Time blocks you add show up here.',
      );
    }
    return ListView(
      children: [
        for (final d in days) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '${_months[d.month - 1]} ${d.day}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final b in blocksOnDay(blocks, d)) BlockTile(block: b),
        ],
      ],
    );
  }
}

class _Week extends StatelessWidget {
  const _Week({
    required this.start,
    required this.blocks,
    required this.onPick,
  });
  final DateTime start;
  final List<TimeBlock> blocks;
  final ValueChanged<DateTime> onPick;
  static const _names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      for (var i = 0; i < 7; i++)
        Builder(
          builder: (_) {
            final d = addDays(start, i);
            final day = blocksOnDay(blocks, d);
            return ListTile(
              onTap: () => onPick(d),
              title: Text('${_names[i]} ${d.day}'),
              subtitle: Text(
                day.isEmpty
                    ? 'Free'
                    : day
                          .map((b) => '${hhmm(b.startsAt)} ${b.title}')
                          .join('\n'),
              ),
              trailing: Text('${day.length}'),
            );
          },
        ),
    ],
  );
}

class _Month extends StatelessWidget {
  const _Month({required this.day, required this.blocks, required this.onPick});
  final DateTime day;
  final List<TimeBlock> blocks;
  final ValueChanged<DateTime> onPick;
  @override
  Widget build(BuildContext context) {
    final cells = monthCells(day);
    return GridView.count(
      crossAxisCount: 7,
      padding: const EdgeInsets.all(8),
      children: [
        for (final d in cells)
          Builder(
            builder: (_) {
              final n = blocksOnDay(blocks, d).length;
              final inMonth = d.month == day.month;
              return Semantics(
                label: '${_months[d.month - 1]} ${d.day}, $n time blocks',
                button: true,
                child: InkWell(
                  onTap: () => onPick(d),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${d.day}',
                          style: TextStyle(
                            color: inMonth
                                ? null
                                : Theme.of(context).disabledColor,
                          ),
                        ),
                        if (n > 0)
                          Text(
                            '$n •',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Unscheduled tasks. Tapping one books the next free hour on the shown day:
/// the button alternative to drag-and-drop.
class _Tray extends ConsumerWidget {
  const _Tray({required this.ws, required this.day});
  final String ws;
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(_unscheduledProvider).value ?? const <Task>[];
    if (tasks.isEmpty) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            for (final t in tasks.take(20))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  avatar: const Icon(Icons.schedule, size: 16),
                  label: Text(t.title, overflow: TextOverflow.ellipsis),
                  tooltip: 'Schedule on ${_months[day.month - 1]} ${day.day}',
                  onPressed: () => _book(context, ref, t),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _book(BuildContext context, WidgetRef ref, Task t) async {
    final repo = ref.read(timeBlocksRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final base = DateTime(day.year, day.month, day.day, 9);
    final dayBlocks = blocksOnDay(
      await repo.overlapsFor(ws, base.toUtc(), addDays(base, 1).toUtc()),
      day,
    );
    final start = nextFreeStart(dayBlocks, base, const Duration(hours: 1));
    try {
      await repo.create(
        ws: ws,
        title: t.title,
        category: 'focus',
        startsAt: start,
        endsAt: start.add(const Duration(hours: 1)),
        taskId: t.id,
        projectId: t.projectId,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Scheduled at ${hhmm(start)}.')),
      );
    } on AppError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
