import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/backup/backup_providers.dart';
import '../core/db/providers.dart';
import '../core/utils/phone.dart';
import '../core/utils/photos.dart';
import '../core/widgets/common.dart';
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
                            profile?.name ?? 'Thekedaar',
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
                          const Text(
                            'Edit business profile',
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
            item(Icons.home_outlined, 'Home', Routes.dashboard, tab: true),
            heading('Billing'),
            item(Icons.receipt_long_outlined, 'Bills', Routes.billingTab(0),
                tab: true),
            item(Icons.request_quote_outlined, 'Quotations',
                Routes.billingTab(1),
                tab: true),
            item(Icons.people_outline, 'Clients', Routes.billingTab(2),
                tab: true),
            item(Icons.payments_outlined, 'Payments received',
                Routes.billingTab(3),
                tab: true),
            item(Icons.location_city_outlined, 'Jobs / Sites', Routes.jobs),
            heading('Workers & Khata'),
            item(Icons.groups_outlined, 'Workers', Routes.workers, tab: true),
            item(Icons.fact_check_outlined, 'Mark attendance',
                Routes.attendance(),
                tab: true),
            item(Icons.calendar_month_outlined, 'Attendance register',
                Routes.attendanceMonth,
                subtitle: 'All workers, month calendar',
                tab: true),
            item(Icons.account_balance_wallet_outlined, 'Khata balances',
                Routes.khataTab(0),
                tab: true),
            item(Icons.history, 'Khata entries', Routes.khataTab(1), tab: true),
            heading('Expenses'),
            item(Icons.receipt_outlined, 'Expenses', Routes.expenses,
                subtitle: 'Kharcha log, month-wise'),
            item(Icons.store_outlined, 'Suppliers', Routes.suppliers,
                subtitle: 'Udhaar purchases & payments'),
            heading('Reports'),
            item(Icons.account_balance_outlined, 'Lena / Dena', Routes.dues()),
            heading('Settings'),
            item(Icons.store_mall_directory_outlined, 'Business profile',
                Routes.businessProfile),
            item(
              Icons.cloud_upload_outlined,
              'Backup & restore',
              Routes.backup,
              trailing: Icon(Icons.circle, size: 12, color: backupDot),
            ),
            item(Icons.notifications_outlined, 'Reminders', Routes.reminders),
            item(Icons.settings_outlined, 'All settings', Routes.settings,
                subtitle: 'Trades, work rules, app lock'),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
