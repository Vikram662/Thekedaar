import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/widgets/common.dart';
import '../../lock/app_lock_controller.dart';
import '../../lock/lock_screens.dart';

/// PRD C1: change PIN, fingerprint on/off, lock now.
class AppLockSettingsScreen extends ConsumerWidget {
  const AppLockSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('App lock'))),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.pin),
            title: Text(tr('Change PIN')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              if (!await confirmIdentity(context, reason: tr('Enter current PIN'))) {
                return;
              }
              if (!context.mounted) return;
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => const PinSetupScreen(popOnDone: true),
                ),
              );
              if ((changed ?? false) && context.mounted) {
                showMessage(context, tr('PIN changed'));
              }
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: Text(tr('Unlock with fingerprint / face')),
            subtitle: lock.biometricAvailable
                ? null
                : Text(tr('Not available on this phone')),
            value: lock.biometricEnabled,
            onChanged: lock.biometricAvailable
                ? (enabled) async {
                    if (enabled) {
                      // Turn on, then prove a finger works; undo if not.
                      await lock.setBiometricEnabled(true);
                      final confirmed = await lock.authenticateBiometric(
                        reason: tr('Confirm fingerprint'),
                        unlock: false,
                      );
                      if (!confirmed) await lock.setBiometricEnabled(false);
                    } else {
                      await lock.setBiometricEnabled(false);
                    }
                  }
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.lock_clock),
            title: Text(tr('Lock now')),
            subtitle: Text(tr('The app also locks after 2 minutes in the background')),
            onTap: lock.lockNow,
          ),
        ],
      ),
    );
  }
}
