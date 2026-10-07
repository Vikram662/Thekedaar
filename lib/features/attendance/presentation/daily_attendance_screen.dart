import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pickers.dart';
import '../../subscription/presentation/subscription_screen.dart';
import '../data/attendance_repository.dart';
import 'attendance_widgets.dart';

/// PRD AT-01 / AT-02: one list, P / ½ / A per worker, OT stepper,
/// "Mark all present" and "Copy yesterday".
/// Body only; shown inside the Attendance tab (attendance_screen.dart).
class DailyAttendanceView extends ConsumerStatefulWidget {
  const DailyAttendanceView({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  ConsumerState<DailyAttendanceView> createState() =>
      _DailyAttendanceViewState();
}

class _DailyAttendanceViewState extends ConsumerState<DailyAttendanceView> {
  late DateTime _date = dateOnly(widget.initialDate ?? DateTime.now());

  @override
  void didUpdateWidget(DailyAttendanceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final date = widget.initialDate;
    if (date != null && date != oldWidget.initialDate) {
      setState(() => _date = dateOnly(date));
    }
  }

  bool get _isToday => _date == dateOnly(DateTime.now());

  void _shift(int days) {
    final next = DateTime(_date.year, _date.month, _date.day + days);
    if (next.isAfter(dateOnly(DateTime.now()))) return;
    setState(() => _date = next);
  }

  Future<void> _markAll(AttendanceStatus status) async {
    if (!await requirePro(context, ref)) return;
    final count = await ref
        .read(attendanceRepositoryProvider)
        .markAllUnmarked(_date, status);
    if (mounted) {
      showMessage(
        context,
        count == 0 ? tr('Everyone is already marked') : tr('Marked {count} workers', {'count': count}),
      );
    }
  }

  Future<void> _copyYesterday() async {
    if (!await requirePro(context, ref)) return;
    final count = await ref.read(attendanceRepositoryProvider).copyDay(
          from: DateTime(_date.year, _date.month, _date.day - 1),
          to: _date,
        );
    if (mounted) {
      showMessage(
        context,
        count == 0 ? tr('Nothing to copy') : tr('Copied {count} from previous day', {'count': count}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(attendanceDayProvider(isoDate(_date)));
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final isWeeklyOff = settings?.weeklyOffDay == _date.weekday;

    return Column(
      children: [
        Material(
          color: AppColors.surface,
          child: Row(
            children: [
              IconButton(
                tooltip: tr('Previous day'),
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shift(-1),
              ),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await pickDate(
                      context,
                      initial: _date,
                      last: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _date = dateOnly(picked));
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      children: [
                        Text(
                          _isToday ? tr('Today') : dayFormat.format(_date),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (isWeeklyOff)
                          Text(tr('Weekly off'),
                              style: TextStyle(color: AppColors.slate600)),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('Next day'),
                icon: const Icon(Icons.chevron_right),
                onPressed: _isToday ? null : () => _shift(1),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, AppSizes.tapMin),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => _markAll(isWeeklyOff
                      ? AttendanceStatus.off
                      : AttendanceStatus.present),
                  icon: const Icon(Icons.done_all),
                  label:
                      Text(isWeeklyOff ? tr('Mark all Off') : tr('Mark all present')),
                ),
              ),
              const SizedBox(width: AppSizes.gap),
              OutlinedButton.icon(
                onPressed: _copyYesterday,
                icon: const Icon(Icons.content_copy),
                label: Text(tr('Copy yesterday')),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.when(
            loading: () => const ListSkeleton(),
            error: (e, _) => Center(child: Text('$e')),
            data: (list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.groups,
                  title: tr('No workers on this day'),
                  message: tr('Add workers first, or pick a later date.'),
                );
              }
              final marked = list.where((r) => r.attendance != null).length;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(tr('{marked} of {count} marked', {'marked': marked, 'count': list.length}),
                      style: const TextStyle(color: AppColors.slate600)),
                  const SizedBox(height: 8),
                  for (final row in list)
                    _AttendanceRowTile(row: row, date: _date),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AttendanceRowTile extends ConsumerWidget {
  const _AttendanceRowTile({required this.row, required this.date});

  final AttendanceRow row;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = row.attendance?.status;
    final ot = row.attendance?.otMilliHours ?? 0;
    final working =
        current == AttendanceStatus.present || current == AttendanceStatus.half;

    Future<void> mark(AttendanceStatus status) => markAttendance(
          context,
          ref,
          workerId: row.worker.id,
          date: date,
          status: status,
        );

    Future<void> setOt(int milliHours) => markAttendance(
          context,
          ref,
          workerId: row.worker.id,
          date: date,
          status: current,
          otMilliHours: milliHours < 0 ? 0 : milliHours,
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.gap),
      child: Panel(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onLongPress: () => showStatusSheet(
                      context,
                      ref,
                      workerId: row.worker.id,
                      date: date,
                      current: current,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.worker.name,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          current == null
                              ? (row.roleName ?? tr('Not marked'))
                              : statusStyle(current).label,
                          style: TextStyle(
                            color: current == null
                                ? AppColors.slate600
                                : statusStyle(current).color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                for (final status in const [
                  AttendanceStatus.present,
                  AttendanceStatus.half,
                  AttendanceStatus.absent,
                ])
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _StatusButton(
                      status: status,
                      selected: current == status,
                      onTap: () => mark(status),
                    ),
                  ),
              ],
            ),
            if (working)
              Row(
                children: [
                  Text(tr('OT hours')),
                  const Spacer(),
                  IconButton(
                    tooltip: tr('Less OT'),
                    onPressed: ot <= 0 ? null : () => setOt(ot - 500),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      formatMilli(ot),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('More OT'),
                    onPressed: () => setOt(ot + 500),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final AttendanceStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = statusStyle(status);
    return Semantics(
      selected: selected,
      label: style.label,
      button: true,
      child: Material(
        color: selected ? style.color : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radius),
          side: BorderSide(color: style.color, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSizes.radius),
          onTap: onTap,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(style.icon,
                    size: 18, color: selected ? Colors.white : style.color),
                Text(
                  style.short,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : style.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
