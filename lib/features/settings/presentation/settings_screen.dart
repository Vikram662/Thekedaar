import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/backup/backup_providers.dart';
import '../../../core/config.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/widgets/language_picker.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(businessProfileProvider).valueOrNull;
    final backup = ref.watch(backupStateProvider).valueOrNull;
    final trades = profile == null ? <Trade>{} : Trade.decode(profile.trades);

    Widget tile(IconData icon, String title, String? subtitle, String route) =>
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(route),
        );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(
        children: [
          const LanguageTile(),
          tile(Icons.store, tr('Business profile'), profile?.name,
              Routes.businessProfile),
          tile(Icons.handyman, tr('Trades'), trades.map((t) => t.label).join(', '),
              Routes.trades),
          tile(Icons.rule, tr('Work rules'), tr('Monthly salary, weekly off'),
              Routes.rules),
          tile(
            Icons.cloud_upload,
            tr('Backup & restore'),
            backup == null || !backup.configured
                ? tr('Not set up')
                : tr('Google Drive · {email}', {'email': backup.email ?? ''}),
            Routes.backup,
          ),
          tile(Icons.workspace_premium, tr('Thekedaar Pro'),
              tr('₹99/month subscription'), Routes.subscription),
          tile(Icons.lock, tr('App lock'), tr('PIN and fingerprint'), Routes.appLock),
          tile(Icons.notifications, tr('Reminders'),
              tr('Backup, overdue bills, month end'), Routes.reminders),
          const Divider(),
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text(tr('Thekedaar')),
            subtitle: Text(tr('Version {appVersion}', {'appVersion': AppConfig.appVersion})),
          ),
        ],
      ),
    );
  }
}
