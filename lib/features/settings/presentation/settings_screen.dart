import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/backup/backup_providers.dart';
import '../../../core/config.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';

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
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          tile(Icons.store, 'Business profile', profile?.name, Routes.businessProfile),
          tile(Icons.handyman, 'Trades',
              trades.map((t) => t.label).join(', '), Routes.trades),
          tile(Icons.rule, 'Work rules', 'Monthly salary, weekly off',
              Routes.rules),
          tile(
            Icons.cloud_upload,
            'Backup & restore',
            backup == null || !backup.configured
                ? 'Not set up'
                : 'Google Drive · ${backup.email ?? ''}',
            Routes.backup,
          ),
          tile(Icons.lock, 'App lock', 'PIN and fingerprint', Routes.appLock),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Thekedaar'),
            subtitle: Text('Version ${AppConfig.appVersion}'),
          ),
        ],
      ),
    );
  }
}
