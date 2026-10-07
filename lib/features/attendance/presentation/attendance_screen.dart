import 'package:flutter/material.dart';

import '../../../app/app_drawer.dart';
import '../../../app/theme.dart';
import '../../../core/i18n/i18n.dart';
import 'daily_attendance_screen.dart';
import 'month_register_view.dart';

/// Attendance tab: "Today" to mark, "Month" for every worker's calendar.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, this.date, this.showMonth = false});

  /// Day to open in "Today" view (from links like worker detail).
  final DateTime? date;
  final bool showMonth;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late bool _month = widget.showMonth;

  @override
  void didUpdateWidget(AttendanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showMonth != oldWidget.showMonth) _month = widget.showMonth;
    if (widget.date != null && widget.date != oldWidget.date) _month = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(title: Text(tr('Attendance'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppColors.amber500,
                  selectedForegroundColor: AppColors.slate900,
                ),
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.edit_calendar),
                    label: Text(tr('Mark today')),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.calendar_month),
                    label: Text(tr('Month register')),
                  ),
                ],
                selected: {_month},
                onSelectionChanged: (s) => setState(() => _month = s.first),
              ),
            ),
          ),
          Expanded(
            child: _month
                ? const MonthRegisterView()
                : DailyAttendanceView(initialDate: widget.date),
          ),
        ],
      ),
    );
  }
}
