import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      appBar: AppBar(title: const Text('App lock')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.pin),
            title: const Text('Change PIN'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              if (!await confirmIdentity(context, reason: 'Enter current PIN')) {
                return;
              }
              if (!context.mounted) return;
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => const PinSetupScreen(popOnDone: true),
                ),
              );
              if ((changed ?? false) && context.mounted) {
                showMessage(context, 'PIN changed');
              }
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Unlock with fingerprint / face'),
            subtitle: lock.biometricAvailable
                ? null
                : const Text('Not available on this phone'),
            value: lock.biometricEnabled,
            onChanged: lock.biometricAvailable
                ? (enabled) async {
                    if (enabled) {
                      // Turn on, then prove a finger works; undo if not.
                      await lock.setBiometricEnabled(true);
                      final confirmed = await lock.authenticateBiometric(
                        reason: 'Confirm fingerprint',
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
            title: const Text('Lock now'),
            subtitle: const Text('The app also locks after 2 minutes in the background'),
            onTap: lock.lockNow,
          ),
        ],
      ),
    );
  }
}
