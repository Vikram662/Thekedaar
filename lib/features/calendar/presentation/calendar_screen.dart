import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../data/calendar_repository.dart';

DateFormat get _sheetDate => DateFormat('EEEE, d MMMM yyyy', uiDateLocale);

/// Icon and colour for each kind of event.
(IconData, Color) eventStyle(CalendarEventKind kind) => switch (kind) {
      CalendarEventKind.bill => (Icons.receipt_long, AppColors.blue700),
      CalendarEventKind.quotation => (Icons.request_quote, AppColors.slate600),
      CalendarEventKind.paymentIn =>
        (Icons.call_received, AppColors.successText),
      CalendarEventKind.workerPaid => (Icons.payments, AppColors.dangerText),
      CalendarEventKind.workerOther =>
        (Icons.edit_note, AppColors.warningText),
      CalendarEventKind.pieceWork => (Icons.construction, AppColors.warningText),
      CalendarEventKind.settlement => (Icons.task_alt, AppColors.dangerText),
      CalendarEventKind.expense => (Icons.shopping_cart, AppColors.dangerText),
      CalendarEventKind.purchase => (Icons.local_shipping, AppColors.slate600),
      CalendarEventKind.supplierPaid => (Icons.store, AppColors.dangerText),
      CalendarEventKind.holiday => (Icons.celebration, Color(0xFF7C3AED)),
    };

/// Business calendar: every bill, payment, khata entry, expense, supplier
/// entry, holiday and the day's attendance. View only; tap an entry to open
/// its screen.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(
        calendarMonthProvider((year: _month.year, month: _month.month)));
    final data = async.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Calendar')),
        actions: [
          TextButton(
            onPressed: () => setState(() =>
                _month = DateTime(DateTime.now().year, DateTime.now().month)),
            child: Text(tr('Today')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Panel(
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
                      onPressed: () => _shift(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                if (data == null)
                  const SizedBox(
                    height: 320,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  _MonthGrid(
                    data: data,
                    onTap: (date) => _showDay(context, data, date),
                  ),
              ],
            ),
          ),
          if (data != null) ...[
            const SizedBox(height: 12),
            _MonthTotals(data: data),
          ],
          const SizedBox(height: 12),
          const _Legend(),
        ],
      ),
    );
  }

  void _showDay(BuildContext context, CalendarMonth data, DateTime date) {
    final router = GoRouter.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _DaySheet(
        date: date,
        events: data.on(isoDate(date)),
        attendance: data.attendance[isoDate(date)],
        inPaise: data.inPaise(isoDate(date)),
        outPaise: data.outPaise(isoDate(date)),
        onOpen: (route, {bool tab = false}) {
          Navigator.of(sheetContext).pop();
          if (tab) {
            router.go(route);
          } else {
            router.push(route);
          }
        },
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.data, required this.onTap});

  final CalendarMonth data;
  final void Function(DateTime date) onTap;

  @override
  Widget build(BuildContext context) {
    final month = data.month;
    final firstWeekday = DateTime(month.year, month.month).weekday; // Mon=1
    final days = daysInMonth(month);
    final today = isoDate(DateTime.now());

    return Column(
      children: [
        Row(
          children: [
            for (final d in weekdayLetters)
              Expanded(
                child: Center(
                  child: Text(d,
                      style: const TextStyle(
                          color: AppColors.slate600,
                          fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 0.78,
          children: [
            for (var i = 1; i < firstWeekday; i++) const SizedBox(),
            for (var day = 1; day <= days; day++)
              _DayCell(
                date: DateTime(month.year, month.month, day),
                isToday:
                    isoDate(DateTime(month.year, month.month, day)) == today,
                data: data,
                onTap: onTap,
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isToday,
    required this.data,
    required this.onTap,
  });

  final DateTime date;
  final bool isToday;
  final CalendarMonth data;
  final void Function(DateTime date) onTap;

  @override
  Widget build(BuildContext context) {
    final iso = isoDate(date);
    final events = data.on(iso);
    final attendance = data.attendance[iso];
    final holiday = events.any((e) => e.kind == CalendarEventKind.holiday);
    // One dot per kind, at most 4.
    final kinds = <CalendarEventKind>{
      for (final e in events)
        if (e.kind != CalendarEventKind.holiday) e.kind,
    }.take(4).toList();
    final hasAnything = events.isNotEmpty || attendance != null;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onTap(date),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: isToday
              ? AppColors.amber100
              : holiday
                  ? const Color(0xFFF3E8FF)
                  : hasAnything
                      ? AppColors.surface2
                      : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isToday ? AppColors.amber500 : AppColors.border,
            width: isToday ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            if (attendance != null && attendance.present + attendance.half > 0)
              Text(
                tr('P {count}', {'count': attendance.present + attendance.half}),
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.successText,
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final k in kinds)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: eventStyle(k).$2,
                      shape: BoxShape.circle,
                    ),
                  ),
                if (kinds.isEmpty) const SizedBox(height: 6),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthTotals extends StatelessWidget {
  const _MonthTotals({required this.data});

  final CalendarMonth data;

  @override
  Widget build(BuildContext context) {
    var inTotal = 0;
    var outTotal = 0;
    var entries = 0;
    for (final date in data.events.keys) {
      inTotal += data.inPaise(date);
      outTotal += data.outPaise(date);
      entries += data.on(date).length;
    }
    Widget stat(String label, String value, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppColors.slate600, fontSize: 12)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        );
    return Panel(
      child: Row(
        children: [
          stat(tr('Money in'), formatPaise(inTotal), AppColors.successText),
          stat(tr('Money out'), formatPaise(outTotal), AppColors.dangerText),
          stat(tr('Entries'), '$entries', AppColors.slate900),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        dot(AppColors.successText, tr('Money in')),
        dot(AppColors.dangerText, tr('Money out')),
        dot(AppColors.blue700, tr('Bill')),
        dot(AppColors.warningText, tr('Khata / work')),
        dot(AppColors.slate600, tr('Quotation / purchase')),
        dot(const Color(0xFF7C3AED), tr('Holiday')),
        Text(tr('P = workers present'),
            style: TextStyle(fontSize: 12, color: AppColors.slate600)),
      ],
    );
  }
}

/// Everything on one day, view only. Tapping a row opens its screen.
class _DaySheet extends StatelessWidget {
  const _DaySheet({
    required this.date,
    required this.events,
    required this.attendance,
    required this.inPaise,
    required this.outPaise,
    required this.onOpen,
  });

  final DateTime date;
  final List<CalendarEvent> events;
  final DayAttendance? attendance;
  final int inPaise;
  final int outPaise;
  final void Function(String route, {bool tab}) onOpen;

  @override
  Widget build(BuildContext context) {
    final att = attendance;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(_sheetDate.format(date),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: tr('In'),
                  value: formatPaise(inPaise),
                  color: AppColors.successText,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: tr('Out'),
                  value: formatPaise(outPaise),
                  color: AppColors.dangerText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Material(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              tileColor: Colors.transparent,
              leading: const Icon(Icons.fact_check, color: AppColors.successText),
              title: Text(tr('Attendance')),
              subtitle: Text(att == null || att.isEmpty
                  ? tr('Not marked')
                  : tr('Present {present} · Half {half} · Absent {absent}', {'present': att.present, 'half': att.half, 'absent': att.absent})),
              trailing: const Icon(Icons.chevron_right),
              // Future days can't be marked yet.
              onTap: date.isAfter(DateTime.now())
                  ? null
                  : () => onOpen(Routes.attendance(date), tab: true),
            ),
          ),
          const SizedBox(height: 8),
          if (events.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(tr('No bills, payments or expenses on this day'),
                    style: TextStyle(color: AppColors.slate600)),
              ),
            )
          else
            for (final e in events) _EventTile(event: e, onOpen: onOpen),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(label, style: TextStyle(color: color)),
            const Spacer(),
            Text(value,
                style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.onOpen});

  final CalendarEvent event;
  final void Function(String route, {bool tab}) onOpen;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = eventStyle(event.kind);
    final amount = event.amountPaise;
    final sign = switch (event.flow) {
      MoneyFlow.incoming => '+ ',
      MoneyFlow.outgoing => '- ',
      MoneyFlow.none => '',
    };
    final route = event.route;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      tileColor: Colors.transparent,
      leading: CircleAvatar(
        backgroundColor: color.withAlpha(28),
        foregroundColor: color,
        child: Icon(icon, size: 20),
      ),
      title: Text(event.title,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: event.subtitle == null || event.subtitle!.isEmpty
          ? null
          : Text(event.subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: amount == null
          ? (route == null ? null : const Icon(Icons.chevron_right))
          : Text(
              '$sign${formatPaise(amount)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: switch (event.flow) {
                  MoneyFlow.incoming => AppColors.successText,
                  MoneyFlow.outgoing => AppColors.dangerText,
                  MoneyFlow.none => AppColors.slate900,
                },
              ),
            ),
      onTap: route == null ? null : () => onOpen(route),
    );
  }
}
