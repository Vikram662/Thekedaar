import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_drawer.dart';
import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/backup/backup_providers.dart';
import '../../../core/backup/clock_check.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../backup/presentation/backup_screen.dart';
import '../../reports/presentation/dues_screen.dart';
import '../../tasks/data/tasks_repository.dart';
import '../../workers/data/workers_repository.dart';

final _presentTodayProvider = StreamProvider<List<Worker>>(
  (ref) =>
      ref.watch(attendanceRepositoryProvider).watchPresentOn(DateTime.now()),
);

/// PRD E2 / DB-01..DB-03: greeting with Lena / Dena, quick actions,
/// today's attendance.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backup = ref.watch(backupStateProvider).valueOrNull;

    return Scaffold(
      // All sections are in the side menu (☰); bottom tabs keep the main 5.
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(tr('Home')),
        actions: [
          if (backup != null) _BackupDot(state: backup),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const _BackupProgressCard(),
          if (backup != null) _BackupBanner(state: backup),
          const _HeroCard(),
          const SizedBox(height: 20),
          const _QuickActions(),
          const SizedBox(height: 20),
          const _TasksPreviewCard(),
          const SizedBox(height: 20),
          const _TodayCard(),
        ],
      ),
    );
  }
}

/// Greeting + business name + Lena / Dena totals on a dark gradient card.
class _HeroCard extends ConsumerWidget {
  const _HeroCard();

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return tr('Good morning');
    if (hour < 17) return tr('Good afternoon');
    return tr('Good evening');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(businessProfileProvider).valueOrNull;
    final report = ref.watch(duesReportProvider).valueOrNull;
    final overdue = report?.overdueTotal ?? 0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.slate900, Color(0xFF1E3A5F)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330F172A),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_greeting()} 👋',
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            profile?.name ?? tr('Thekedaar'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            DateFormat('EEEE, d MMMM', uiDateLocale).format(DateTime.now()),
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: tr('Lena (to receive)'),
                  value: report == null ? '…' : formatPaise(report.lenaTotal),
                  icon: Icons.south_west,
                  accent: AppColors.amber500,
                  note: overdue > 0
                      ? tr('Overdue {amount}', {'amount': formatPaise(overdue)})
                      : null,
                  onTap: () => context.push(Routes.dues(0)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroStat(
                  label: tr('Dena (to pay)'),
                  value: report == null ? '…' : formatPaise(report.denaTotal),
                  icon: Icons.north_east,
                  accent: const Color(0xFF34D399),
                  onTap: () => context.push(Routes.dues(1)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.note,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x1AFFFFFF),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: accent),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFFCBD5E1), fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                note ?? ' ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four big round shortcuts, each with its own colour.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _QuickAction(
          icon: Icons.receipt_long,
          label: tr('New Bill'),
          tint: const Color(0xFFDBEAFE),
          iconColor: AppColors.blue700,
          onTap: () => context.push(Routes.newDocument(DocumentKind.invoice)),
        ),
        _QuickAction(
          icon: Icons.payments,
          label: tr('Advance'),
          tint: AppColors.amber100,
          iconColor: AppColors.warningText,
          onTap: () =>
              context.push(Routes.ledgerEntry(type: LedgerType.advance)),
        ),
        _QuickAction(
          icon: Icons.fact_check,
          label: tr('Attendance'),
          tint: const Color(0xFFD1FAE5),
          iconColor: AppColors.successText,
          onTap: () => context.go(Routes.attendance()),
        ),
        _QuickAction(
          icon: Icons.receipt,
          label: tr('Expense'),
          tint: const Color(0xFFFFE4E6),
          iconColor: AppColors.dangerText,
          onTap: () => context.push(Routes.addExpense),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.tint,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 28, color: iconColor),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick card showing pending/overdue tasks & site visits (Module C8).
class _TasksPreviewCard extends ConsumerWidget {
  const _TasksPreviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingTasksProvider);

    return pendingAsync.when(
      data: (tasks) {
        if (tasks.isEmpty) {
          return Panel(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.amber100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.task_alt, color: AppColors.warningText),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Tasks & Visits'),
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      Text(
                        tr('No pending tasks. Stay on track!'),
                        style: TextStyle(color: AppColors.slate600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => context.push(Routes.addTask),
                  child: Text(tr('+ Add')),
                ),
              ],
            ),
          );
        }

        final now = DateTime.now();
        final overdueCount = tasks.where((t) => t.dueAt.isBefore(now)).length;
        final nextTask = tasks.first;
        final df = DateFormat('dd MMM, hh:mm a', uiDateLocale);

        return Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: overdueCount > 0 ? AppColors.dangerSurface : AppColors.amber100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      overdueCount > 0 ? Icons.notification_important : Icons.task_alt,
                      color: overdueCount > 0 ? AppColors.dangerText : AppColors.warningText,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              tr('Tasks & Visits'),
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            if (overdueCount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.dangerFill,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  tr('{overdueCount} Overdue', {'overdueCount': overdueCount}),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          tr('{count} pending scheduled', {'count': tasks.length}),
                          style: const TextStyle(color: AppColors.slate600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push(Routes.tasks),
                    child: Text(tr('View all')),
                  ),
                ],
              ),
              const Divider(height: 20),
              InkWell(
                onTap: () => context.push(Routes.tasks),
                child: Row(
                  children: [
                    Icon(
                      nextTask.taskType.icon,
                      size: 18,
                      color: AppColors.slate600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        nextTask.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      df.format(nextTask.dueAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: nextTask.dueAt.isBefore(now)
                            ? AppColors.dangerText
                            : AppColors.slate600,
                        fontWeight: nextTask.dueAt.isBefore(now)
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Who is present today, out of all active workers (PRD DB-03).
class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final present = ref.watch(_presentTodayProvider).valueOrNull ?? const [];
    final total = ref.watch(activeWorkersProvider).valueOrNull?.length ?? 0;
    final textTheme = Theme.of(context).textTheme;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Today'), style: textTheme.titleMedium),
                    Text(
                      total == 0
                          ? tr('No workers added yet')
                          : tr('{count} of {total} workers present', {'count': present.length, 'total': total}),
                      style: const TextStyle(color: AppColors.slate600),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                onPressed: () => context.go(
                    total == 0 ? Routes.workers : Routes.attendance()),
                icon: Icon(total == 0 ? Icons.person_add : Icons.edit_calendar),
                label: Text(total == 0 ? tr('Add') : tr('Mark')),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: present.length / total,
                minHeight: 8,
                backgroundColor: AppColors.border,
                color: AppColors.successFill,
              ),
            ),
          ],
          if (present.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: present.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final w = present[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.push(Routes.worker(w.id)),
                    child: SizedBox(
                      width: 56,
                      child: Column(
                        children: [
                          Badge(
                            backgroundColor: AppColors.successFill,
                            label: const Icon(Icons.check,
                                size: 10, color: Colors.white),
                            child: CircleAvatar(
                              backgroundColor: AppColors.amber100,
                              foregroundColor: AppColors.slate900,
                              child: Text(initials(w.name)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            w.name.split(' ').first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Backup dot in the header (PRD DB-01, D3.1): green / amber / red.
class _BackupDot extends ConsumerWidget {
  const _BackupDot({required this.state});

  final BackupState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (color, label) = switch (state.health) {
      BackupHealth.synced => (AppColors.successFill, tr('Backed up')),
      BackupHealth.pending => (AppColors.amber500, tr('Backup pending')),
      BackupHealth.failed => (AppColors.dangerFill, tr('Backup problem')),
      BackupHealth.notSetUp => (AppColors.dangerFill, tr('Backup not set up')),
    };
    return IconButton(
      tooltip: label,
      onPressed: () => _showBackupSheet(context, ref, label, color),
      icon: Stack(
        alignment: Alignment.bottomRight,
        children: [
          const Icon(Icons.cloud_outlined),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cloud button: status, Backup now and backup settings.
void _showBackupSheet(
  BuildContext context,
  WidgetRef ref,
  String label,
  Color color,
) {
  // Actions use the Home screen's context and ref, which outlive the sheet.
  showModalBottomSheet<void>(
    context: context,
    builder: (_) => Consumer(
      builder: (sheetContext, sheetRef, _) {
        final state = sheetRef.watch(backupStateProvider).valueOrNull;
        final running = sheetRef.watch(backupRunningProvider);
        final last = state?.lastBackupAt;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.circle, size: 12, color: color),
                    const SizedBox(width: 8),
                    Text(label,
                        style: Theme.of(sheetContext).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  last == null
                      ? tr('No backup yet')
                      : tr('Last backup: {date}', {'date': dayTimeFormat.format(last)}),
                  style: const TextStyle(color: AppColors.slate600),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: running
                      ? null
                      : () {
                          Navigator.of(sheetContext).pop();
                          runManualBackup(context, ref);
                        },
                  icon: const Icon(Icons.backup),
                  label: Text(running ? tr('Backing up…') : tr('Backup now')),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    context.push(Routes.backup);
                  },
                  icon: const Icon(Icons.settings_backup_restore),
                  label: Text(tr('Backup settings & restore')),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Live % while a backup runs in the app.
class _BackupProgressCard extends ConsumerWidget {
  const _BackupProgressCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(backupProgressProvider);
    if (progress == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.cloud_upload, color: AppColors.blue700),
            const SizedBox(width: 12),
            Expanded(
              child: PercentProgress(
                value: progress.fraction,
                label: progress.step,
                detail: progress.detail,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Red banner when backup is missing, failing or stuck (PRD D1, I-M2, D3.1).
class _BackupBanner extends StatelessWidget {
  const _BackupBanner({required this.state});

  final BackupState state;

  @override
  Widget build(BuildContext context) {
    final String? message = switch (state.health) {
      BackupHealth.notSetUp =>
        tr('Backup not set up. Your data is only on this phone.'),
      BackupHealth.failed => state.blocked
          ? tr('Backup stopped: this data was restored on another phone.')
          : '${tr('No backup in the last 24 hours.')} ${tr(state.lastError ?? '')}',
      BackupHealth.pending => state.pendingTooLong
          ? tr('Backup pending for over a day. Connect to the internet.')
          : null,
      BackupHealth.synced => null,
    };
    final skew = state.clockSkew;
    if (message == null && skew != null) {
      return _banner(
        context,
        Icons.schedule,
        tr('Phone time is {skew} compared to Google. Turn on automatic date & time in phone settings.', {'skew': describeClockSkew(skew)}),
      );
    }
    if (message == null) return const SizedBox.shrink();
    return _banner(context, Icons.cloud_off, message);
  }

  Widget _banner(BuildContext context, IconData icon, String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.dangerSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFFECDD3)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          tileColor: Colors.transparent,
          leading: Icon(icon, color: AppColors.dangerText),
          title: Text(
            message,
            style: const TextStyle(
              color: AppColors.dangerText,
              fontWeight: FontWeight.w600,
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.backup),
        ),
      ),
    );
  }
}
