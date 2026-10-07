import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/audit.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../subscription/presentation/subscription_screen.dart';
import '../data/attendance_repository.dart';

/// Icon + short label + colour per status (PRD I-D3: never colour alone).
class StatusStyle {
  const StatusStyle(this.short, this.label, this.icon, this.color);

  final String short;
  final String label;
  final IconData icon;
  final Color color;
}

StatusStyle statusStyle(AttendanceStatus status) => switch (status) {
      AttendanceStatus.present =>
        StatusStyle('P', tr('Present'), Icons.check, AppColors.successText),
      AttendanceStatus.half => StatusStyle(
          '½', tr('Half day'), Icons.timelapse, AppColors.warningText),
      AttendanceStatus.absent =>
        StatusStyle('A', tr('Absent'), Icons.close, AppColors.dangerText),
      AttendanceStatus.leavePaid => StatusStyle(
          'PL', tr('Paid leave'), Icons.beach_access, AppColors.blue700),
      AttendanceStatus.leaveUnpaid => StatusStyle(
          'UL', tr('Unpaid leave'), Icons.event_busy, AppColors.slate600),
      AttendanceStatus.off => StatusStyle(
          'Off', tr('Weekly off'), Icons.weekend, AppColors.slate600),
    };

/// Sets one worker's status for one day, showing lock errors as a message.
Future<void> markAttendance(
  BuildContext context,
  WidgetRef ref, {
  required String workerId,
  required DateTime date,
  required AttendanceStatus? status,
  int? otMilliHours,
}) async {
  if (!await requirePro(context, ref)) return;
  try {
    final repo = ref.read(attendanceRepositoryProvider);
    if (status == null) {
      await repo.clear(workerId, date);
    } else {
      await repo.setStatus(
        workerId: workerId,
        date: date,
        status: status,
        otMilliHours: otMilliHours,
      );
    }
    HapticFeedback.mediumImpact();
  } on PeriodLockedException catch (e) {
    if (context.mounted) showMessage(context, e.message);
  }
}

/// Bottom sheet with every status, for the calendar and long-press.
Future<void> showStatusSheet(
  BuildContext context,
  WidgetRef ref, {
  required String workerId,
  required DateTime date,
  AttendanceStatus? current,
}) async {
  final choice = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(dayFormat.format(date),
              style: Theme.of(context).textTheme.titleMedium),
          for (final status in AttendanceStatus.values)
            ListTile(
              leading: Icon(statusStyle(status).icon,
                  color: statusStyle(status).color),
              title: Text(statusStyle(status).label),
              trailing: status == current
                  ? const Icon(Icons.check_circle, color: AppColors.successText)
                  : null,
              onTap: () => Navigator.of(context).pop(status),
            ),
          if (current != null)
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: Text(tr('Clear mark')),
              onTap: () => Navigator.of(context).pop('clear'),
            ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  await markAttendance(
    context,
    ref,
    workerId: workerId,
    date: date,
    status: choice is AttendanceStatus ? choice : null,
  );
}

/// Month grid for one worker (PRD AT-04). Tap a day to change it.
class AttendanceCalendar extends ConsumerStatefulWidget {
  const AttendanceCalendar(
      {super.key, required this.worker, this.initialMonth});

  final Worker worker;

  /// Month shown first; defaults to the current month.
  final DateTime? initialMonth;

  @override
  ConsumerState<AttendanceCalendar> createState() => _AttendanceCalendarState();
}

class _AttendanceCalendarState extends ConsumerState<AttendanceCalendar> {
  late DateTime _month = DateTime(
    (widget.initialMonth ?? DateTime.now()).year,
    (widget.initialMonth ?? DateTime.now()).month,
  );

  void _shift(int months) => setState(
        () => _month = DateTime(_month.year, _month.month + months),
      );

  @override
  Widget build(BuildContext context) {
    final marks = ref
            .watch(workerMonthAttendanceProvider((
              workerId: widget.worker.id,
              year: _month.year,
              month: _month.month,
            )))
            .valueOrNull ??
        const <String, Attendance>{};
    final today = dateOnly(DateTime.now());
    final joined = parseIsoDate(widget.worker.joinDate);
    final firstWeekday = DateTime(_month.year, _month.month).weekday; // Mon=1
    final days = daysInMonth(_month);
    final isCurrentMonth =
        _month.year == today.year && _month.month == today.month;

    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: tr('Previous month'),
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  monthFormat.format(_month),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: tr('Next month'),
                onPressed: isCurrentMonth ? null : () => _shift(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Row(
            children: [
              for (final d in weekdayLetters)
                Expanded(
                  child: Center(
                    child: Text(d,
                        style: const TextStyle(color: AppColors.slate600)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (var i = 1; i < firstWeekday; i++) const SizedBox(),
              for (var day = 1; day <= days; day++)
                _DayCell(
                  date: DateTime(_month.year, _month.month, day),
                  mark:
                      marks[isoDate(DateTime(_month.year, _month.month, day))],
                  enabled: !DateTime(_month.year, _month.month, day)
                          .isAfter(today) &&
                      !DateTime(_month.year, _month.month, day)
                          .isBefore(joined),
                  onTap: (date, mark) => showStatusSheet(
                    context,
                    ref,
                    workerId: widget.worker.id,
                    date: date,
                    current: mark?.status,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _MonthTotals(marks: marks.values),
        ],
      ),
    );
  }
}

/// "P 22 · ½ 2 · A 1 …" for one worker's month.
class _MonthTotals extends StatelessWidget {
  const _MonthTotals({required this.marks});

  final Iterable<Attendance> marks;

  @override
  Widget build(BuildContext context) {
    final counts = <AttendanceStatus, int>{};
    for (final m in marks) {
      counts.update(m.status, (v) => v + 1, ifAbsent: () => 1);
    }
    if (counts.isEmpty) {
      return Text(tr('Nothing marked this month'),
          style: TextStyle(color: AppColors.slate600));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final status in AttendanceStatus.values)
          if (counts[status] != null)
            StatusChip(
              label: '${statusStyle(status).short} ${counts[status]}',
              color: statusStyle(status).color,
              icon: statusStyle(status).icon,
            ),
      ],
    );
  }
}

/// One worker's month calendar in a bottom sheet (from the register).
Future<void> showWorkerAttendanceSheet(
  BuildContext context,
  Worker worker,
  DateTime month,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.amber100,
                  foregroundColor: AppColors.slate900,
                  child: Text(initials(worker.name)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    worker.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final router = GoRouter.of(context);
                    Navigator.of(context).pop();
                    router.push(Routes.worker(worker.id));
                  },
                  child: Text(tr('Open worker')),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tr('Tap a day to change it.'),
              style: TextStyle(color: AppColors.slate600),
            ),
            const SizedBox(height: 12),
            AttendanceCalendar(worker: worker, initialMonth: month),
          ],
        ),
      ),
    );

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.mark,
    required this.enabled,
    required this.onTap,
  });

  final DateTime date;
  final Attendance? mark;
  final bool enabled;
  final void Function(DateTime date, Attendance? mark) onTap;

  @override
  Widget build(BuildContext context) {
    final style = mark == null ? null : statusStyle(mark!.status);
    return Semantics(
      label: '${date.day}: ${style?.label ?? 'not marked'}',
      button: enabled,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? () => onTap(date, mark) : null,
        child: Container(
          decoration: BoxDecoration(
            color: style?.color.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: style?.color ?? AppColors.border,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 12,
                  color: enabled ? AppColors.slate900 : AppColors.border,
                ),
              ),
              if (style != null)
                Text(
                  style.short,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: style.color,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
