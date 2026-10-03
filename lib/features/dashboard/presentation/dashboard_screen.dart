import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/backup/backup_providers.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/widgets/common.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../reports/presentation/dues_screen.dart';

final _presentTodayProvider = StreamProvider<List<Worker>>(
  (ref) =>
      ref.watch(attendanceRepositoryProvider).watchPresentOn(DateTime.now()),
);

/// PRD E2 / DB-01..DB-03.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(businessProfileProvider).valueOrNull;
    final backup = ref.watch(backupStateProvider).valueOrNull;
    final present = ref.watch(_presentTodayProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(profile?.name ?? 'Thekedaar'),
        actions: [
          if (backup != null) _BackupDot(state: backup),
          PopupMenuButton<String>(
            onSelected: (route) => context.push(route),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: Routes.attendance(),
                child: const ListTile(
                  leading: Icon(Icons.fact_check),
                  title: Text('Attendance'),
                ),
              ),
              PopupMenuItem(
                value: Routes.dues(),
                child: const ListTile(
                  leading: Icon(Icons.account_balance),
                  title: Text('Lena / Dena report'),
                ),
              ),
              const PopupMenuItem(
                value: Routes.settings,
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Settings'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          if (backup != null) _BackupBanner(state: backup),
          const DuesSummaryCard(),
          const SectionTitle('Quick actions'),
          Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.receipt_long,
                  label: '+ New Bill',
                  onTap: () =>
                      context.push(Routes.newDocument(DocumentKind.invoice)),
                ),
              ),
              const SizedBox(width: AppSizes.gap),
              Expanded(
                child: _QuickAction(
                  icon: Icons.payments,
                  label: '+ Advance',
                  onTap: () => context.push(
                      Routes.ledgerEntry(type: LedgerType.advance)),
                ),
              ),
              const SizedBox(width: AppSizes.gap),
              Expanded(
                child: _QuickAction(
                  icon: Icons.fact_check,
                  label: "Today's Attendance",
                  onTap: () => context.push(Routes.attendance()),
                ),
              ),
            ],
          ),
          SectionTitle(
            'Present today (${present.length})',
            trailing: TextButton(
              onPressed: () => context.push(Routes.attendance()),
              child: const Text('Mark'),
            ),
          ),
          if (present.isEmpty)
            const Text('No one marked present yet today.',
                style: TextStyle(color: AppColors.slate600))
          else
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: present.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final w = present[i];
                  return InkWell(
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
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Backup dot in the header (PRD DB-01, D3.1): green / amber / red.
class _BackupDot extends StatelessWidget {
  const _BackupDot({required this.state});

  final BackupState state;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state.health) {
      BackupHealth.synced => (AppColors.successFill, 'Backed up'),
      BackupHealth.pending => (AppColors.amber500, 'Backup pending'),
      BackupHealth.failed => (AppColors.dangerFill, 'Backup problem'),
      BackupHealth.notSetUp => (AppColors.dangerFill, 'Backup not set up'),
    };
    return IconButton(
      tooltip: label,
      onPressed: () => context.push(Routes.backup),
      icon: Stack(
        alignment: Alignment.bottomRight,
        children: [
          const Icon(Icons.cloud),
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

/// Red banner when backup is missing, failing or stuck (PRD D1, I-M2, D3.1).
class _BackupBanner extends StatelessWidget {
  const _BackupBanner({required this.state});

  final BackupState state;

  @override
  Widget build(BuildContext context) {
    final String? message = switch (state.health) {
      BackupHealth.notSetUp => 'Backup not set up. Your data is only on this phone.',
      BackupHealth.failed => state.blocked
          ? 'Backup stopped: this data was restored on another phone.'
          : 'No backup in the last 24 hours. ${state.lastError ?? ''}',
      BackupHealth.pending => state.pendingTooLong
          ? 'Backup pending for over a day. Connect to the internet.'
          : null,
      BackupHealth.synced => null,
    };
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.gutter),
      child: Material(
        color: AppColors.dangerSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radius),
          side: const BorderSide(color: AppColors.dangerFill),
        ),
        child: ListTile(
          leading: const Icon(Icons.cloud_off, color: AppColors.dangerText),
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

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.amber500,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radius),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.radius),
        onTap: onTap,
        child: SizedBox(
          height: 96,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 30, color: AppColors.slate900),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(
                    color: AppColors.slate900,
                    fontWeight: FontWeight.w700,
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
