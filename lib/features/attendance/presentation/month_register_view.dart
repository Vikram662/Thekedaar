import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/attendance_repository.dart';
import 'attendance_widgets.dart';

const _nameWidth = 112.0;
const _cellWidth = 36.0;
const _rowHeight = 44.0;
const _totalWidth = 44.0;

/// All workers × all days of a month. Each cell shows P / ½ / A / Off / L;
/// tap a cell to change it (PRD AT-04).
class MonthRegisterView extends ConsumerStatefulWidget {
  const MonthRegisterView({super.key});

  @override
  ConsumerState<MonthRegisterView> createState() => _MonthRegisterViewState();
}

class _MonthRegisterViewState extends ConsumerState<MonthRegisterView> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  final _horizontal = ScrollController();

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  @override
  void initState() {
    super.initState();
    // Start scrolled near today in the current month.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_horizontal.hasClients || !_isCurrentMonth) return;
      final target = (DateTime.now().day - 6) * _cellWidth;
      _horizontal.jumpTo(
        target.clamp(0, _horizontal.position.maxScrollExtent).toDouble(),
      );
    });
  }

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final register = ref.watch(
      monthRegisterProvider((year: _month.year, month: _month.month)),
    );
    final weeklyOff = ref.watch(appSettingsProvider).valueOrNull?.weeklyOffDay;

    return Column(
      children: [
        Material(
          color: AppColors.surface,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shift(-1),
              ),
              Expanded(
                child: Text(
                  monthFormat.format(_month),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right),
                onPressed: _isCurrentMonth ? null : () => _shift(1),
              ),
            ],
          ),
        ),
        const _Legend(),
        Expanded(
          child: register.when(
            loading: () => const ListSkeleton(),
            error: (e, _) => Center(child: Text('$e')),
            data: (r) => r.workers.isEmpty
                ? const EmptyState(
                    icon: Icons.groups,
                    title: 'No workers this month',
                    message: 'Add workers to see the attendance register.',
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _NameColumn(workers: r.workers),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _horizontal,
                            scrollDirection: Axis.horizontal,
                            child: _Grid(register: r, weeklyOff: weeklyOff),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final s in const [
            AttendanceStatus.present,
            AttendanceStatus.half,
            AttendanceStatus.absent,
            AttendanceStatus.off,
            AttendanceStatus.leavePaid,
          ])
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Mark(status: s, size: 22),
                const SizedBox(width: 4),
                Text(statusStyle(s).label, style: const TextStyle(fontSize: 12)),
              ],
            ),
        ],
      ),
    );
  }
}

class _NameColumn extends StatelessWidget {
  const _NameColumn({required this.workers});

  final List<Worker> workers;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _nameWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            height: _rowHeight,
            child: Padding(
              padding: EdgeInsets.only(left: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Worker',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          for (final w in workers)
            Container(
              height: _rowHeight,
              padding: const EdgeInsets.only(left: 12, right: 4),
              alignment: Alignment.centerLeft,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Text(
                w.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: w.isActive ? AppColors.slate900 : AppColors.slate600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Grid extends ConsumerWidget {
  const _Grid({required this.register, required this.weeklyOff});

  final MonthRegister register;
  final int? weeklyOff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = register.month;
    final today = DateTime.now();
    final todayDay = month.year == today.year && month.month == today.month
        ? today.day
        : null;
    const weekLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    Widget header(String top, String bottom, {bool highlight = false}) =>
        Container(
          width: _cellWidth,
          height: _rowHeight,
          color: highlight ? AppColors.amber100 : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(top,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
              Text(bottom,
                  style:
                      const TextStyle(fontSize: 10, color: AppColors.slate600)),
            ],
          ),
        );

    Widget total(String text, {bool bold = false}) => SizedBox(
          width: _totalWidth,
          height: _rowHeight,
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var d = 1; d <= register.days; d++)
              header(
                '$d',
                weekLetters[DateTime(month.year, month.month, d).weekday - 1],
                highlight: d == todayDay,
              ),
            header('P', 'days'),
            header('½', 'days'),
            header('A', 'days'),
            header('Paid', 'days'),
          ],
        ),
        for (final w in register.workers)
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                for (var d = 1; d <= register.days; d++)
                  _Cell(
                    worker: w,
                    date: DateTime(month.year, month.month, d),
                    status: register.marks[w.id]?[d],
                    isWeeklyOff: DateTime(month.year, month.month, d).weekday ==
                        weeklyOff,
                    isToday: d == todayDay,
                  ),
                total('${register.count(w.id, AttendanceStatus.present)}'),
                total('${register.count(w.id, AttendanceStatus.half)}'),
                total('${register.count(w.id, AttendanceStatus.absent)}'),
                total(_days(register.paidDays(w.id)), bold: true),
              ],
            ),
          ),
      ],
    );
  }

  static String _days(double d) =>
      d == d.roundToDouble() ? '${d.toInt()}' : d.toStringAsFixed(1);
}

class _Cell extends ConsumerWidget {
  const _Cell({
    required this.worker,
    required this.date,
    required this.status,
    required this.isWeeklyOff,
    required this.isToday,
  });

  final Worker worker;
  final DateTime date;
  final AttendanceStatus? status;
  final bool isWeeklyOff;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final future = date.isAfter(DateTime(today.year, today.month, today.day));
    final beforeJoin = date.isBefore(parseIsoDate(worker.joinDate));
    final enabled = !future && !beforeJoin;

    return InkWell(
      onTap: enabled
          ? () => showStatusSheet(
                context,
                ref,
                workerId: worker.id,
                date: date,
                current: status,
              )
          : null,
      child: Container(
        width: _cellWidth,
        height: _rowHeight,
        color: isToday
            ? AppColors.amber100
            : isWeeklyOff
                ? AppColors.surface2
                : null,
        alignment: Alignment.center,
        child: status != null
            ? _Mark(status: status!, size: 28)
            : Text(
                enabled ? '·' : '',
                style: const TextStyle(color: AppColors.border, fontSize: 18),
              ),
      ),
    );
  }

}

/// Coloured letter badge: P / ½ / A / Off / PL / UL.
class _Mark extends StatelessWidget {
  const _Mark({required this.status, required this.size});

  final AttendanceStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = statusStyle(status);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.color.withAlpha(36),
        border: Border.all(color: style.color),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        style.short,
        style: TextStyle(
          fontSize: style.short.length > 1 ? 9 : 13,
          fontWeight: FontWeight.w800,
          color: style.color,
        ),
      ),
    );
  }
}
