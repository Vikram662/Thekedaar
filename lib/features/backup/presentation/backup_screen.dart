import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/backup/backup_engine.dart';
import '../../../core/backup/backup_providers.dart';
import '../../../core/backup/drive_store.dart';
import '../../../core/backup/keyring.dart';
import '../../../core/config.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/meta_store.dart';
import '../../../core/db/providers.dart';
import '../../../core/security/secure_store.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/widgets/common.dart';
import '../../lock/app_lock_controller.dart';
import '../../lock/lock_screens.dart';

String backupResultMessage(BackupResult result) => switch (result.outcome) {
      BackupOutcome.success => 'Backup done ✓',
      BackupOutcome.waitingForInternet =>
        'No internet. Backup will upload by itself when internet is back.',
      BackupOutcome.skipped => result.message ?? 'Nothing to back up',
      BackupOutcome.notSetUp => 'Backup is not set up',
      _ => result.message ?? 'Backup failed',
    };

String _size(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).ceil()} KB';

final _driveQuotaProvider = FutureProvider.autoDispose<DriveQuota?>((ref) async {
  final client = await ref.read(googleDriveAuthProvider).client();
  if (client == null) return null;
  try {
    return await DriveStore(client).quota();
  } finally {
    client.close();
  }
});

/// PRD D7 Backup screen.
class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(backupStateProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: state == null
          ? const ListSkeleton()
          : !AppConfig.driveConfigured
              ? const _NotAvailable()
              : state.configured
                  ? _BackupDashboard(state: state)
                  : const _BackupSetupFlow(),
    );
  }
}

class _NotAvailable extends StatelessWidget {
  const _NotAvailable();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSizes.gutter),
      children: [
        const Panel(
          child: Text(
            'Google Drive backup is not switched on in this app build yet. '
            'It needs the Google Cloud OAuth client id (PRD D-7). '
            'Your data is only on this phone until then.',
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => context.push(Routes.restore),
          icon: const Icon(Icons.file_open),
          label: const Text('Restore from a backup file'),
        ),
      ],
    );
  }
}

// ─── Setup (PRD D1) ─────────────────────────────────────────────────────────

class _BackupSetupFlow extends ConsumerStatefulWidget {
  const _BackupSetupFlow();

  @override
  ConsumerState<_BackupSetupFlow> createState() => _BackupSetupFlowState();
}

class _BackupSetupFlowState extends ConsumerState<_BackupSetupFlow> {
  int _step = 0;
  String? _email;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final String _recoveryKey = generateRecoveryKey();
  bool _keyWritten = false;
  bool _wifiOnly = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final lock = ref.read(appLockProvider);
    lock.suspendRelock = true;
    try {
      final email = await ref.read(googleDriveAuthProvider).connect();
      setState(() {
        _email = email;
        _step = 1;
      });
    } catch (e) {
      setState(() => _error = 'Could not connect: $e');
    } finally {
      lock.suspendRelock = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  void _checkPassword() {
    final pw = _password.text;
    if (pw.length < 8) {
      setState(() => _error = 'Use at least 8 characters');
    } else if (pw != _confirm.text) {
      setState(() => _error = 'Passwords do not match');
    } else {
      setState(() {
        _error = null;
        _step = 2;
      });
    }
  }

  Future<void> _createKeys() async {
    setState(() => _busy = true);
    try {
      final created = await Keyring.create(
        password: _password.text,
        recoveryKey: _recoveryKey,
      );
      final db = ref.read(databaseProvider);
      final meta = MetaStore(db);
      await ref.read(secureStoreProvider).write(
            SecureStore.backupMasterKey,
            encodeMasterKey(created.masterKey),
          );
      await meta.set(MetaKeys.keyring, created.keyring.toJsonString());
      await meta.set(MetaKeys.driveEmail, _email!);
      // This phone is the one setting up backup, so it becomes active.
      await meta.setBool(MetaKeys.claimDevice, true);
      setState(() => _step = 3);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    final settings = await ref.read(appSettingsProvider.future);
    await ref
        .read(settingsRepositoryProvider)
        .saveSettings(settings.copyWith(backupWifiOnly: _wifiOnly));
    await MetaStore(ref.read(databaseProvider))
        .setBool(MetaKeys.backupConfigured, true);
    try {
      await ref
          .read(backupSchedulerProvider)
          .schedulePeriodic(wifiOnly: _wifiOnly);
    } catch (_) {}
    final result = await ref
        .read(backupCoordinatorProvider)
        .runNow(BackupTrigger.manual);
    if (mounted) showMessage(context, backupResultMessage(result));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final error = _error == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: AppColors.dangerText)),
          );

    final body = switch (_step) {
      0 => [
          const Icon(Icons.cloud_upload, size: 56),
          const SizedBox(height: 12),
          Text('Protect your data', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Your data is saved only on this phone. Connect your Google Drive '
            'and the app backs up automatically 4 times a day, and as soon as '
            'internet is back. The app can see only its own backup files in '
            'your Drive.',
          ),
          error,
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _connect,
            icon: const Icon(Icons.login),
            label: const Text('Connect Google Drive'),
          ),
          TextButton(
            onPressed: () => context.push(Routes.restore),
            child: const Text('Restore an existing backup instead'),
          ),
        ],
      1 => [
          Text('Set a Backup Password', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Connected: $_email'),
          const SizedBox(height: 8),
          const Text(
            'Backups are locked with this password before upload. You need it '
            'to restore on a new phone.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password (min 8)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password again'),
          ),
          error,
          const SizedBox(height: 16),
          FilledButton(onPressed: _checkPassword, child: const Text('Next')),
        ],
      2 => [
          Text('Your Recovery Key', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'If you forget the password, this key opens your backups. '
            'Write it on paper and keep it safe. Without the password AND '
            'this key, backups can never be opened.',
            style: TextStyle(color: AppColors.dangerText),
          ),
          const SizedBox(height: 16),
          Panel(
            child: SelectableText(
              _recoveryKey,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _recoveryKey));
              if (context.mounted) showMessage(context, 'Copied');
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _keyWritten,
            onChanged: (v) => setState(() => _keyWritten = v ?? false),
            title: const Text('I have written down the Recovery Key'),
          ),
          error,
          const SizedBox(height: 8),
          FilledButton(
            onPressed: !_keyWritten || _busy ? null : _createKeys,
            child: _busy
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : const Text('Next'),
          ),
        ],
      _ => [
          Text('Almost done', style: textTheme.titleLarge),
          const SizedBox(height: 12),
          RadioListTile<bool>(
            contentPadding: EdgeInsets.zero,
            value: false,
            groupValue: _wifiOnly,
            onChanged: (v) => setState(() => _wifiOnly = v ?? false),
            title: const Text('Wi-Fi + mobile data'),
            subtitle: const Text('Recommended: backups are small'),
          ),
          RadioListTile<bool>(
            contentPadding: EdgeInsets.zero,
            value: true,
            groupValue: _wifiOnly,
            onChanged: (v) => setState(() => _wifiOnly = v ?? true),
            title: const Text('Wi-Fi only'),
          ),
          const SizedBox(height: 12),
          const Panel(
            child: Text(
              'On Xiaomi, Oppo, Vivo, Realme and some other phones, turn off '
              'battery saving for this app so auto backup is not stopped:\n'
              'Settings → Apps → Thekedaar → Battery → No restrictions.',
            ),
          ),
          const SizedBox(height: 16),
          if (_busy && ref.watch(backupProgressProvider) != null) ...[
            Builder(builder: (context) {
              final p = ref.watch(backupProgressProvider)!;
              return PercentProgress(
                value: p.fraction,
                label: p.step,
                detail: p.detail,
              );
            }),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _busy ? null : _finish,
            child: _busy
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : const Text('Finish and back up now'),
          ),
        ],
    };

    return ListView(
      padding: const EdgeInsets.all(AppSizes.gutter),
      children: [
        LinearProgressIndicator(value: (_step + 1) / 4),
        const SizedBox(height: 24),
        ...body,
      ],
    );
  }
}

// ─── Dashboard (PRD D7) ─────────────────────────────────────────────────────

class _BackupDashboard extends ConsumerWidget {
  const _BackupDashboard({required this.state});

  final BackupState state;

  Future<void> _backupNow(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(backupCoordinatorProvider)
        .runNow(BackupTrigger.manual);
    if (context.mounted) showMessage(context, backupResultMessage(result));
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final engine = ref.read(backupEngineProvider);
    final file = await engine.latestLocalSnapshot() ??
        (await engine.createLocalSnapshot(BackupTrigger.manual)).file;
    final lock = ref.read(appLockProvider);
    lock.suspendRelock = true;
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: 'Thekedaar backup file. Keep it safe; it opens only with your '
            'Backup Password or Recovery Key.',
      ));
    } finally {
      lock.suspendRelock = false;
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    if (!await confirmIdentity(context, reason: 'Confirm to change password')) {
      return;
    }
    if (!context.mounted) return;
    final password = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Backup Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password (min 8)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password again'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final newPassword = password.text;
    final matches = newPassword == confirm.text;
    password.dispose();
    confirm.dispose();
    if (ok != true || !context.mounted) return;
    if (newPassword.length < 8 || !matches) {
      showMessage(context, 'Password must be 8+ characters and match');
      return;
    }
    final meta = MetaStore(ref.read(databaseProvider));
    final ringJson = await meta.get(MetaKeys.keyring);
    final keyEncoded =
        await ref.read(secureStoreProvider).read(SecureStore.backupMasterKey);
    if (ringJson == null || keyEncoded == null) return;
    final masterKey = keyEncoded.split(',').map(int.parse).toList();
    final ring = await Keyring.fromJsonString(ringJson)
        .withNewPassword(masterKey, newPassword);
    await meta.set(MetaKeys.keyring, ring.toJsonString());
    if (context.mounted) {
      showMessage(context, 'Password changed. Old backups open with it too.');
    }
    await ref.read(backupCoordinatorProvider).runNow(BackupTrigger.manual);
  }

  Future<void> _reconnect(BuildContext context, WidgetRef ref) async {
    final lock = ref.read(appLockProvider);
    lock.suspendRelock = true;
    try {
      final email = await ref.read(googleDriveAuthProvider).connect();
      if (state.email != null &&
          email.toLowerCase() != state.email!.toLowerCase()) {
        if (context.mounted) {
          showMessage(context, 'Please choose the account ${state.email}');
        }
        return;
      }
      await MetaStore(ref.read(databaseProvider)).remove(MetaKeys.lastBackupError);
      if (context.mounted) await _backupNow(context, ref);
    } catch (e) {
      if (context.mounted) showMessage(context, 'Could not connect: $e');
    } finally {
      lock.suspendRelock = false;
    }
  }

  Future<void> _turnOff(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Turn off backup?',
      message: 'Backups already on Drive stay there. New changes will only '
          'be on this phone.',
      confirmLabel: 'Turn off',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    if (!await confirmIdentity(context, reason: 'Confirm to turn off backup')) {
      return;
    }
    await MetaStore(ref.read(databaseProvider))
        .setBool(MetaKeys.backupConfigured, false);
    try {
      await ref.read(backupSchedulerProvider).cancelBackups();
      await ref.read(googleDriveAuthProvider).disconnect();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(backupRunningProvider);
    final progress = ref.watch(backupProgressProvider);
    final history = ref.watch(backupHistoryProvider).valueOrNull ?? const [];
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final quota = ref.watch(_driveQuotaProvider).valueOrNull;
    final lastSuccess = history
        .where((l) => l.status == BackupStatus.success)
        .firstOrNull;
    final disconnected =
        state.lastError?.toLowerCase().contains('disconnected') ?? false;

    final (statusText, statusColor) = state.blocked
        ? ('Stopped: data moved to another phone', AppColors.dangerText)
        : state.health == BackupHealth.failed
            ? (state.lastError ?? 'No backup in 24 hours', AppColors.dangerText)
            : state.health == BackupHealth.pending
                ? (
                    '${state.pendingChanges} change${state.pendingChanges == 1 ? '' : 's'} '
                        'waiting to upload',
                    AppColors.warningText
                  )
                : ('All data backed up', AppColors.successText);

    return ListView(
      padding: const EdgeInsets.all(AppSizes.gutter),
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_done),
                  const SizedBox(width: 8),
                  Expanded(child: Text(state.email ?? 'Google Drive')),
                ],
              ),
              const Divider(),
              Text(
                state.lastBackupAt == null
                    ? 'Last backup: never'
                    : 'Last backup: ${dayTimeFormat.format(state.lastBackupAt!)}',
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.circle, size: 12, color: statusColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(statusText, style: TextStyle(color: statusColor)),
                  ),
                ],
              ),
              if (lastSuccess?.sizeBytes != null || quota?.freeBytes != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    [
                      if (lastSuccess?.sizeBytes != null)
                        'Size ${_size(lastSuccess!.sizeBytes!)}',
                      if (quota?.freeBytes != null)
                        'Drive free ${_size(quota!.freeBytes!)}',
                    ].join(' · '),
                    style: const TextStyle(color: AppColors.slate600),
                  ),
                ),
              if ((quota?.usedFraction ?? 0) > 0.9)
                const Text(
                  'Google Drive is almost full (PRD I-M11). Free some space.',
                  style: TextStyle(color: AppColors.dangerText),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (running && progress != null) ...[
          Panel(
            child: PercentProgress(
              value: progress.fraction,
              label: progress.step,
              detail: progress.detail,
            ),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed: running ? null : () => _backupNow(context, ref),
          icon: running
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.backup),
          label: Text(running ? 'Backing up…' : 'Backup Now'),
        ),
        if (disconnected)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: () => _reconnect(context, ref),
              icon: const Icon(Icons.link),
              label: const Text('Reconnect Google Drive'),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.push(Routes.restore),
          icon: const Icon(Icons.restore),
          label: const Text('Restore'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _download(context, ref),
          icon: const Icon(Icons.download),
          label: const Text('Download backup file'),
        ),
        const SectionTitle('Settings'),
        if (settings != null) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: const Text('Auto backup times'),
            subtitle: Text(settings.backupSlots
                .map((h) => '${h.toString().padLeft(2, '0')}:00')
                .join(' · ')),
            trailing: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 3, label: Text('3×')),
                ButtonSegment(value: 4, label: Text('4×')),
              ],
              selected: {settings.backupSlots.length == 3 ? 3 : 4},
              onSelectionChanged: (s) => ref
                  .read(settingsRepositoryProvider)
                  .saveSettings(settings.copyWith(
                    backupSlots: s.first == 3
                        ? AppSettings.threeBackupSlots
                        : AppSettings.defaultBackupSlots,
                  )),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.wifi),
            title: const Text('Wi-Fi only'),
            value: settings.backupWifiOnly,
            onChanged: (v) async {
              await ref
                  .read(settingsRepositoryProvider)
                  .saveSettings(settings.copyWith(backupWifiOnly: v));
              try {
                await ref
                    .read(backupSchedulerProvider)
                    .schedulePeriodic(wifiOnly: v);
              } catch (_) {}
            },
          ),
        ],
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.password),
          title: const Text('Change Backup Password'),
          onTap: () => _changePassword(context, ref),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cloud_off, color: AppColors.dangerText),
          title: const Text('Turn off backup'),
          onTap: () => _turnOff(context, ref),
        ),
        const SectionTitle('History'),
        for (final log in history.take(15))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              switch (log.status) {
                BackupStatus.success => Icons.check_circle,
                BackupStatus.failed => Icons.error,
                BackupStatus.skipped => Icons.remove_circle_outline,
              },
              color: switch (log.status) {
                BackupStatus.success => AppColors.successText,
                BackupStatus.failed => AppColors.dangerText,
                BackupStatus.skipped => AppColors.slate600,
              },
            ),
            title: Text(dayTimeFormat
                .format(DateTime.fromMillisecondsSinceEpoch(log.startedAt))),
            subtitle: Text([
              _triggerLabel(log.triggerType),
              if (log.sizeBytes != null) _size(log.sizeBytes!),
              if (log.status == BackupStatus.failed && log.error != null)
                log.error!,
            ].join(' · ')),
          ),
      ],
    );
  }

  static String _triggerLabel(BackupTrigger trigger) => switch (trigger) {
        BackupTrigger.scheduled => 'Auto',
        BackupTrigger.onChange => 'On change',
        BackupTrigger.manual => 'Manual',
        BackupTrigger.internetBack => 'Internet back',
        BackupTrigger.preRestore => 'Before restore',
      };
}
