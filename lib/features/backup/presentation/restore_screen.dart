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
      fail(_useRecoveryKey ? 'Wrong Recovery Key' : 'Wrong Backup Password');
    } on RestoreException catch (e) {
      fail(e.message);
    } on BackupFormatException catch (e) {
      fail(e.message);
    } catch (e) {
      fail('$e');
    } finally {
      lock.suspendRelock = false;
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
    return null;
  }

  Future<void> _fromDrive() async {
    await _run('Connecting to Google Drive…', () async {
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
        setState(() => _error = 'No backups found in $email');
      }
    });
  }

  Future<void> _fromFile() async {
    await _run('Opening file…', () async {
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
          ? 'Enter the Recovery Key'
          : 'Enter the Backup Password');
      return;
    }
    final hasData = ref.read(businessProfileProvider).valueOrNull != null;
    if (hasData) {
      final ok = await confirmDialog(
        context,
        title: 'Replace data on this phone?',
        message: 'Everything on this phone will be replaced by the backup. '
            'A copy of the current data is backed up first.',
        confirmLabel: 'Restore',
        destructive: true,
      );
      if (!ok || !mounted) return;
      if (!await confirmIdentity(context, reason: 'Confirm to restore')) return;
    }

    await _run('Restoring…', () async {
      final service = _service;
      final fromDrive = _chosenDrive != null;
      setState(() => _status = 'Downloading…');
      final bytes = fromDrive
          ? await service.downloadBackup(_chosenDrive!.id)
          : _fileBytes!;
      final keyring = fromDrive ? await service.driveKeyring() : null;
      setState(() => _status = 'Unlocking…');
      final prepared = await service.prepare(
        bytes,
        password: _useRecoveryKey ? null : secret,
        recoveryKey: _useRecoveryKey ? secret : null,
        keyring: keyring,
      );
      if (hasData) {
        // PRD D6: PRE_RESTORE backup so the restore can be undone.
        setState(() => _status = 'Backing up current data…');
        try {
          await ref
              .read(backupEngineProvider)
              .run(BackupTrigger.preRestore, force: true);
        } catch (_) {
          // A local `.pre_restore` copy is kept regardless.
        }
      }
      setState(() => _status = 'Replacing data…');
      final email = _driveEmail;
      await ref.read(databaseReplacerProvider)(
        (path) => service.writeDatabase(prepared, path),
        (db) => service.afterRestore(db, prepared, driveEmail: email),
      );
      // The app restarts on the restored data; this screen is gone now.
    });
  }

  @override
  Widget build(BuildContext context) {
    final manifest = _chosenDrive == null ? _fileHeader?.manifest : null;
    final ready = _chosenDrive != null || _fileBytes != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Restore')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.gutter),
          children: [
            const Text('Where is your backup?'),
            const SizedBox(height: 8),
            if (AppConfig.driveConfigured)
              OutlinedButton.icon(
                onPressed: _fromDrive,
                icon: const Icon(Icons.cloud_download),
                label: const Text('Google Drive'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _fromFile,
              icon: const Icon(Icons.file_open),
              label: const Text('Backup file (.tkbak)'),
            ),
            if (_driveBackups != null && _driveBackups!.isNotEmpty) ...[
              const SectionTitle('Choose a backup'),
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
              const SectionTitle('Backup file'),
              Panel(
                child: Text(
                  '${dayTimeFormat.format(manifest.createdAt)}\n'
                  '${_describe(manifest.counts, _fileBytes!.length)}',
                ),
              ),
            ],
            if (ready) ...[
              const SectionTitle('Unlock'),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Backup Password')),
                  ButtonSegment(value: true, label: Text('Recovery Key')),
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
                      _useRecoveryKey ? 'XXXX-XXXX-XXXX-…' : 'Backup Password',
                ),
              ),
            ],
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  children: [
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(_status!),
                  ],
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
              label: 'Restore',
              busy: _busy,
              onPressed: _restore,
            )
          : null,
    );
  }

  static String _describe(Map<String, int> counts, int sizeBytes) {
    final parts = [
      if (counts['workers'] != null) '${counts['workers']} workers',
      if (counts['invoices'] != null) '${counts['invoices']} bills',
      if (counts['clients'] != null) '${counts['clients']} clients',
      '${(sizeBytes / 1024).ceil()} KB',
    ];
    return parts.join(' · ');
  }
}
