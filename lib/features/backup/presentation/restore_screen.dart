import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/backup/backup_format.dart';
import '../../../core/backup/backup_providers.dart';
import '../../../core/backup/keyring.dart';
import '../../../core/backup/restore_service.dart';
import '../../../core/config.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/security/secure_store.dart';
import '../../../core/widgets/common.dart';
import '../../lock/app_lock_controller.dart';
import '../../lock/lock_screens.dart';

/// PRD D6: restore from Google Drive or from a `.tkbak` file.
class RestoreScreen extends ConsumerStatefulWidget {
  const RestoreScreen({super.key});

  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  List<DriveBackupInfo>? _driveBackups;
  DriveBackupInfo? _chosenDrive;
  Uint8List? _fileBytes;
  BackupHeader? _fileHeader;
  String? _driveEmail;
  final _secret = TextEditingController();
  bool _useRecoveryKey = false;
  bool _busy = false;
  String? _status;

  /// 0.0 – 1.0 while restoring, null for steps without a known size.
  double? _progress;
  String? _progressDetail;
  String? _error;

  RestoreService get _service => RestoreService(
        auth: ref.read(googleDriveAuthProvider),
        secureStore: ref.read(secureStoreProvider),
      );

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  Future<T?> _run<T>(String status, Future<T> Function() action) async {
    setState(() {
      _busy = true;
      _status = status;
      _error = null;
    });
    final lock = ref.read(appLockProvider);
    lock.suspendRelock = true;
    void fail(String message) {
      if (mounted) setState(() => _error = message);
    }

    try {
      return await action();
    } on WrongSecretException {
      fail(_useRecoveryKey ? tr('Wrong Recovery Key') : tr('Wrong Backup Password'));
    } on RestoreException catch (e) {
      fail(tr(e.message));
    } on BackupFormatException catch (e) {
      fail(tr(e.message));
    } catch (e) {
      fail(errorText(e));
    } finally {
      lock.suspendRelock = false;
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
          _progress = null;
          _progressDetail = null;
        });
      }
    }
    return null;
  }

  Future<void> _fromDrive() async {
    await _run(tr('Connecting to Google Drive…'), () async {
      final email = await ref.read(googleDriveAuthProvider).connect();
      final backups = await _service.listDriveBackups();
      if (!mounted) return;
      setState(() {
        _driveEmail = email;
        _driveBackups = backups;
        _chosenDrive = backups.isEmpty ? null : backups.first;
        _fileBytes = null;
        _fileHeader = null;
      });
      if (backups.isEmpty) {
        setState(() => _error = tr('No backups found in {email}', {'email': email}));
      }
    });
  }

  Future<void> _fromFile() async {
    await _run(tr('Opening file…'), () async {
      final result = await FilePicker.platform.pickFiles();
      final path = result?.files.single.path;
      if (path == null) return;
      final bytes = await File(path).readAsBytes();
      final header = readBackupHeader(bytes);
      if (!mounted) return;
      setState(() {
        _fileBytes = bytes;
        _fileHeader = header;
        _driveBackups = null;
        _chosenDrive = null;
      });
    });
  }

  Future<void> _restore() async {
    final secret = _secret.text.trim();
    if (secret.isEmpty) {
      setState(() => _error = _useRecoveryKey
          ? tr('Enter the Recovery Key')
          : tr('Enter the Backup Password'));
      return;
    }
    final hasData = ref.read(businessProfileProvider).valueOrNull != null;
    if (hasData) {
      final ok = await confirmDialog(
        context,
        title: tr('Replace data on this phone?'),
        message: tr('Everything on this phone will be replaced by the backup. A copy of the current data is backed up first.'),
        confirmLabel: tr('Restore'),
        destructive: true,
      );
      if (!ok || !mounted) return;
      if (!await confirmIdentity(context, reason: tr('Confirm to restore'))) return;
    }

    await _run(tr('Restoring…'), () async {
      final service = _service;
      final fromDrive = _chosenDrive != null;
      _step(tr('Downloading backup'), 0.02);
      final bytes = fromDrive
          ? await service.downloadBackup(
              _chosenDrive!.id,
              onProgress: (got, total) => _step(
                tr('Downloading backup'),
                total == null || total == 0 ? null : 0.6 * got / total,
                total == null
                    ? null
                    : tr('{got} MB of {total} MB', {'got': _mb(got), 'total': _mb(total)}),
              ),
            )
          : _fileBytes!;
      final keyring = fromDrive ? await service.driveKeyring() : null;
      _step(tr('Unlocking with your key'), 0.65);
      final prepared = await service.prepare(
        bytes,
        password: _useRecoveryKey ? null : secret,
        recoveryKey: _useRecoveryKey ? secret : null,
        keyring: keyring,
      );
      if (hasData) {
        // PRD D6: PRE_RESTORE backup so the restore can be undone.
        _step(tr('Backing up current data'), 0.7);
        final engine = ref.read(backupEngineProvider);
        // The backup's own % fills the 70–90% part of the restore bar.
        engine.onProgress = (p) => _step(
              tr('Backing up current data'),
              0.7 + 0.2 * p.fraction,
              p.detail == null ? p.step : '${p.step} · ${p.detail}',
            );
        try {
          await engine.run(BackupTrigger.preRestore, force: true);
        } catch (_) {
          // A local `.pre_restore` copy is kept regardless.
        } finally {
          engine.onProgress = null;
        }
      }
      _step(tr('Replacing data'), 0.92);
      final email = _driveEmail;
      await ref.read(databaseReplacerProvider)(
        (path) => service.writeDatabase(prepared, path),
        (db) => service.afterRestore(db, prepared, driveEmail: email),
      );
      // The app restarts on the restored data; this screen is gone now.
    });
  }

  void _step(String status, double? progress, [String? detail]) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _progress = progress;
      _progressDetail = detail;
    });
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final manifest = _chosenDrive == null ? _fileHeader?.manifest : null;
    final ready = _chosenDrive != null || _fileBytes != null;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Restore'))),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.gutter),
          children: [
            Text(tr('Where is your backup?')),
            const SizedBox(height: 8),
            if (AppConfig.driveConfigured)
              OutlinedButton.icon(
                onPressed: _fromDrive,
                icon: const Icon(Icons.cloud_download),
                label: Text(tr('Google Drive')),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _fromFile,
              icon: const Icon(Icons.file_open),
              label: Text(tr('Backup file (.tkbak)')),
            ),
            if (_driveBackups != null && _driveBackups!.isNotEmpty) ...[
              SectionTitle(tr('Choose a backup')),
              for (final b in _driveBackups!.take(30))
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: b.id,
                  groupValue: _chosenDrive?.id,
                  onChanged: (_) => setState(() => _chosenDrive = b),
                  title: Text(dayTimeFormat.format(b.createdAt)),
                  subtitle: Text(_describe(b.counts, b.sizeBytes)),
                ),
            ],
            if (manifest != null) ...[
              SectionTitle(tr('Backup file')),
              Panel(
                child: Text(
                  '${dayTimeFormat.format(manifest.createdAt)}\n'
                  '${_describe(manifest.counts, _fileBytes!.length)}',
                ),
              ),
            ],
            if (ready) ...[
              SectionTitle(tr('Unlock')),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: false, label: Text(tr('Backup Password'))),
                  ButtonSegment(value: true, label: Text(tr('Recovery Key'))),
                ],
                selected: {_useRecoveryKey},
                onSelectionChanged: (s) =>
                    setState(() => _useRecoveryKey = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _secret,
                obscureText: !_useRecoveryKey,
                textCapitalization: _useRecoveryKey
                    ? TextCapitalization.characters
                    : TextCapitalization.none,
                decoration: InputDecoration(
                  labelText:
                      _useRecoveryKey ? 'XXXX-XXXX-XXXX-…' : tr('Backup Password'),
                ),
              ),
            ],
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Panel(
                  child: PercentProgress(
                    value: _progress,
                    label: _status!,
                    detail: _progressDetail,
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.dangerText)),
              ),
          ],
        ),
      ),
      bottomNavigationBar: ready
          ? BottomActionBar(
              label: tr('Restore'),
              busy: _busy,
              onPressed: _restore,
            )
          : null,
    );
  }

  static String _describe(Map<String, int> counts, int sizeBytes) {
    final parts = [
      if (counts['workers'] != null)
        tr('{count} workers', {'count': counts['workers']}),
      if (counts['invoices'] != null)
        tr('{count} bills', {'count': counts['invoices']}),
      if (counts['clients'] != null)
        tr('{count} clients', {'count': counts['clients']}),
      '${(sizeBytes / 1024).ceil()} KB',
    ];
    return parts.join(' · ');
  }
}
