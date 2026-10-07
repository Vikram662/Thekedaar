import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/backup/backup_providers.dart';
import '../core/db/enums.dart';
import '../core/db/providers.dart';
import '../core/i18n/i18n.dart';
import '../core/utils/phone.dart';
import '../core/utils/photos.dart';
import '../core/widgets/common.dart';
import '../core/widgets/language_picker.dart';
import '../features/backup/presentation/backup_screen.dart';
import 'router.dart';
import 'theme.dart';

/// Side menu with every section of the app (PRD E1 header menu).
/// Bottom tabs stay for the 4 most used sections.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(businessProfileProvider).valueOrNull;
    final backup = ref.watch(backupStateProvider).valueOrNull;
    final location = GoRouterState.of(context).uri.toString();

    /// [tab] = open a bottom-tab section; otherwise push a page on top.
    Widget item(
      IconData icon,
      String title,
      String route, {
      String? subtitle,
      bool tab = false,
      Widget? trailing,
    }) {
      final selected = tab && location == route;
      return ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: trailing,
        selected: selected,
        selectedTileColor: AppColors.amber100,
        selectedColor: AppColors.slate900,
        onTap: () {
          Navigator.of(context).pop(); // close the drawer
          if (tab) {
            context.go(route);
          } else {
            context.push(route);
          }
        },
      );
    }

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.slate600,
            ),
          ),
        );

    final backupDot = switch (backup?.health) {
      BackupHealth.synced => AppColors.successFill,
      BackupHealth.pending => AppColors.amber500,
      _ => AppColors.dangerFill,
    };

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Business profile header → opens the profile screen.
            InkWell(
              onTap: () {
                Navigator.of(context).pop();
                context.push(Routes.businessProfile);
              },
              child: Container(
                color: AppColors.slate900,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Row(
                  children: [
                    if (profile?.logoPath != null)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.all(3),
                        child: PhotoThumb(
                          key: ValueKey(profile!.logoPath),
                          name: profile!.logoPath!,
                          size: 46,
                          fit: BoxFit.contain,
                        ),
                      )
                    else
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: AppColors.amber500,
                        foregroundColor: AppColors.slate900,
                        child: Text(
                          initials(profile?.name ?? 'T'),
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile?.name ?? tr('Thekedaar'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (profile?.phone != null)
                            Text(
                              formatIndianPhone(profile!.phone!),
                              style: const TextStyle(color: Color(0xFFCBD5E1)),
                            ),
                          Text(
                            tr('Edit business profile'),
                            style: TextStyle(
                              color: AppColors.amber500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            item(Icons.home_outlined, tr('Home'), Routes.dashboard, tab: true),
            heading(tr('Billing')),
            item(Icons.receipt_long_outlined, tr('Bills'), Routes.billingTab(0),
                tab: true),
            item(Icons.request_quote_outlined, tr('Quotations'),
                Routes.billingTab(1),
                tab: true),
            item(Icons.people_outline, tr('Clients'), Routes.billingTab(2),
                tab: true),
            item(Icons.payments_outlined, tr('Payments received'),
                Routes.billingTab(3),
                tab: true),
            item(Icons.location_city_outlined, tr('Jobs / Sites'), Routes.jobs),
            heading(tr('Workers & Khata')),
            item(Icons.groups_outlined, tr('Workers'), Routes.workers, tab: true),
            item(Icons.fact_check_outlined, tr('Mark attendance'),
                Routes.attendance(),
                tab: true),
            item(Icons.calendar_month_outlined, tr('Attendance register'),
                Routes.attendanceMonth,
                subtitle: tr('All workers, month calendar'), tab: true),
            item(Icons.account_balance_wallet_outlined, tr('Khata balances'),
                Routes.khataTab(0),
                tab: true),
            item(Icons.history, tr('Khata entries'), Routes.khataTab(1), tab: true),
            heading(tr('Expenses')),
            item(Icons.receipt_outlined, tr('Expenses'), Routes.expenses,
                subtitle: tr('Kharcha log, month-wise')),
            item(Icons.store_outlined, tr('Suppliers'), Routes.suppliers,
                subtitle: tr('Udhaar purchases & payments')),
            heading(tr('Reports & Tasks')),
            item(Icons.task_alt_outlined, tr('Tasks & Reminders'), Routes.tasks,
                subtitle: tr('Site visits, payments & alerts')),
            item(Icons.calendar_month_outlined, tr('Calendar'), Routes.calendar,
                subtitle: tr('What happened on each day')),
            item(Icons.account_balance_outlined, tr('Lena / Dena'), Routes.dues()),
            heading(tr('Settings')),
            const LanguageTile(closeDrawer: true),
            item(Icons.store_mall_directory_outlined, tr('Business profile'),
                Routes.businessProfile),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: Text(tr('Backup now')),
              subtitle: Text(tr('Upload to Google Drive')),
              onTap: () {
                // The drawer closes; keep what we need from its context.
                final messenger = ScaffoldMessenger.of(context);
                final router = GoRouter.of(context);
                final coordinator = ref.read(backupCoordinatorProvider);
                final running = ref.read(backupRunningProvider);
                Navigator.of(context).pop();
                if (backup == null || !backup.configured) {
                  router.push(Routes.backup);
                  return;
                }
                void say(String text) => messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(text)));
                if (running) {
                  say(tr('Backup is already running'));
                  return;
                }
                say(tr('Backup started…'));
                coordinator
                    .runNow(BackupTrigger.manual)
                    .then((r) => say(backupResultMessage(r)));
              },
            ),
            item(
              Icons.cloud_upload_outlined,
              tr('Backup & restore'),
              Routes.backup,
              trailing: Icon(Icons.circle, size: 12, color: backupDot),
            ),
            item(Icons.notifications_active_outlined, tr('Notification settings'),
                Routes.notificationSettings),
            item(Icons.workspace_premium_outlined, tr('Thekedaar Pro'),
                Routes.subscription,
                subtitle: tr('₹99/month · Manage plan')),
            item(Icons.settings_outlined, tr('All settings'), Routes.settings,
                subtitle: tr('Trades, work rules, app lock')),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
