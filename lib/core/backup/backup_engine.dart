import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../db/database.dart';
import '../db/enums.dart';
import '../db/meta_store.dart';
import '../notify/reminders.dart';
import '../security/secure_store.dart';
import '../utils/ids.dart';
import '../utils/photo_store.dart';
import 'backup_format.dart';
import 'clock_check.dart';
import 'drive_store.dart';
import 'google_drive_auth.dart';
import 'keyring.dart';
import 'retention.dart';

enum BackupOutcome {
  success,

  /// Nothing changed since the last backup, or another backup is running.
  skipped,

  /// No internet: changes stay pending and upload when it is back (D3.1).
  waitingForInternet,

  /// Drive permission lost; the user must reconnect (PRD I-M9).
  driveDisconnected,

  /// Another phone restored this data and is now the active one (I-M5).
  otherDeviceActive,
  notSetUp,
  failed,
}

class BackupResult {
  const BackupResult(this.outcome, [this.message]);

  final BackupOutcome outcome;
  final String? message;

  bool get shouldRetry =>
      outcome == BackupOutcome.waitingForInternet ||
      outcome == BackupOutcome.failed;
}

/// What a running backup is doing, for the progress bar.
class BackupProgress {
  const BackupProgress(this.step, this.fraction, [this.detail]);

  final String step;

  /// 0.0 – 1.0 for the whole backup.
  final double fraction;
  final String? detail;
}

/// A local encrypted snapshot (`.tkbak`) in app storage.
class LocalSnapshot {
  const LocalSnapshot({
    required this.file,
    required this.manifest,
    required this.bytes,
  });

  final File file;
  final BackupManifest manifest;
  final Uint8List bytes;
}

/// Runs one backup (PRD D4). Works in the app and in the WorkManager
/// background isolate; a lock in `app_meta` keeps two runs from overlapping.
class BackupEngine {
  BackupEngine({
    required this.db,
    SecureStore? secureStore,
    GoogleDriveAuth? auth,
  })  : meta = MetaStore(db),
        secure = secureStore ?? SecureStore(),
        auth = auth ?? GoogleDriveAuth();

  final AppDatabase db;
  final MetaStore meta;
  final SecureStore secure;
  final GoogleDriveAuth auth;

  /// Set by the app to show a progress bar; null in the background job.
  void Function(BackupProgress progress)? onProgress;

  void _report(String step, double fraction, [String? detail]) =>
      onProgress?.call(BackupProgress(step, fraction.clamp(0.0, 1.0), detail));

  static const _localSnapshotsToKeep = 3;
  static const _lockDuration = Duration(minutes: 10);

  Future<bool> isSetUp() async =>
      AppConfig.driveConfigured &&
      await meta.getBool(MetaKeys.backupConfigured) &&
      await secure.read(SecureStore.backupMasterKey) != null;

  Future<BackupResult> run(BackupTrigger trigger, {bool force = false}) async {
    if (!await isSetUp()) return const BackupResult(BackupOutcome.notSetUp);

    final dirtySince = await meta.getInt(MetaKeys.dirtySince);
    if (!force && dirtySince == null && trigger == BackupTrigger.scheduled) {
      return const BackupResult(BackupOutcome.skipped, 'No changes');
    }
    if (!await _acquireLock()) {
      return const BackupResult(BackupOutcome.skipped, 'Already running');
    }

    final logId = newId();
    final startedAt = DateTime.now();
    await db.into(db.backupLogs).insert(BackupLogsCompanion.insert(
          id: logId,
          triggerType: trigger,
          status: BackupStatus.skipped,
          schemaVersion: AppDatabase.currentSchemaVersion,
          startedAt: startedAt.millisecondsSinceEpoch,
        ));

    http.Client? client;
    try {
      _report('Connecting to Google Drive', 0.02);
      client = await auth.client();
      if (client == null) {
        return await _finish(
          logId,
          const BackupResult(
            BackupOutcome.driveDisconnected,
            'Google Drive disconnected. Please reconnect.',
          ),
        );
      }
      final store = DriveStore(client);
      final rootId = await _rootFolder(store);
      final dbFolderId = await _dbFolder(store, rootId);

      final deviceId = await secure.deviceId();
      final device = await store.readJson(rootId, DriveStore.deviceFileName);
      final activeDevice = device?['activeDeviceId'] as String?;
      final claiming = await meta.getBool(MetaKeys.claimDevice);
      if (!claiming && activeDevice != null && activeDevice != deviceId) {
        await meta.setBool(MetaKeys.backupBlocked, true);
        return await _finish(
          logId,
          const BackupResult(
            BackupOutcome.otherDeviceActive,
            'This data has moved to another phone. Backup is stopped here.',
          ),
        );
      }

      _report('Preparing your data', 0.08);
      final snapshot = await _latestOrNewSnapshot(trigger);
      final totalBytes = snapshot.bytes.length;
      _report('Uploading backup', 0.12, _sizeText(0, totalBytes));
      final fileId = await _withRetry(() => store.upload(
            onProgress: (sent, total) => _report(
              'Uploading backup',
              0.12 + 0.68 * sent / total,
              _sizeText(sent, total),
            ),
            folderId: dbFolderId,
            name: snapshotName(snapshot.manifest),
            bytes: snapshot.bytes,
            appProperties: {
              'trigger': trigger.name,
              'schema': '${snapshot.manifest.schemaVersion}',
              for (final e in snapshot.manifest.counts.entries)
                e.key: '${e.value}',
            },
          ));

      final serverNow = await _checkClock(store.lastServerTime);
      _report('Saving backup details', 0.84);

      await _ensureKeysUploaded(store, rootId);
      await store.writeJson(rootId, DriveStore.deviceFileName, {
        'activeDeviceId': deviceId,
        'deviceName': 'Android phone',
        'lastBackupAt': DateTime.now().toUtc().toIso8601String(),
        'schemaVersion': AppDatabase.currentSchemaVersion,
      });
      await meta.remove(MetaKeys.claimDevice);

      await (db.update(db.backupLogs)..where((l) => l.id.equals(logId))).write(
        BackupLogsCompanion(
          driveFileId: Value(fileId),
          sizeBytes: Value(snapshot.bytes.length),
          sha256: Value(snapshot.manifest.sha256),
        ),
      );
      await meta.setInt(
          MetaKeys.lastBackupAt, DateTime.now().millisecondsSinceEpoch);
      await meta.remove(MetaKeys.lastBackupError);
      await meta.remove(MetaKeys.backupBlocked);
      // Changes made after the snapshot started stay pending.
      final dirtyNow = await meta.getInt(MetaKeys.dirtySince);
      if (dirtyNow == null ||
          dirtyNow <= snapshot.manifest.createdAt.millisecondsSinceEpoch) {
        await meta.remove(MetaKeys.dirtySince);
        await meta.setInt(MetaKeys.pendingChanges, 0);
      }

      _report('Removing old backups', 0.88);
      await _applyRetention(store, dbFolderId, serverNow);
      try {
        await _uploadPhotos(store, rootId);
      } catch (_) {
        // Photos are incremental: anything missed goes up on the next run.
      }
      _report('Backup complete', 1);
      return await _finish(logId, const BackupResult(BackupOutcome.success));
    } on SocketException catch (e) {
      return await _finish(
        logId,
        BackupResult(BackupOutcome.waitingForInternet, 'No internet: $e'),
      );
    } on http.ClientException catch (e) {
      return await _finish(
        logId,
        BackupResult(BackupOutcome.waitingForInternet, 'Network error: $e'),
      );
    } on TimeoutException {
      return await _finish(
        logId,
        const BackupResult(BackupOutcome.waitingForInternet, 'Network timeout'),
      );
    } catch (e) {
      return await _finish(logId, BackupResult(BackupOutcome.failed, '$e'));
    } finally {
      client?.close();
      await meta.remove(MetaKeys.backupLockUntil);
    }
  }

  /// Writes an encrypted snapshot to app storage (PRD D3.1: local copy as
  /// soon as data changes, even with no internet). Keeps the last 3.
  Future<LocalSnapshot> createLocalSnapshot(BackupTrigger trigger) async {
    final masterKey = await _masterKey();
    final keyringJson = await meta.get(MetaKeys.keyring);
    if (keyringJson == null) throw StateError('Backup keyring missing');

    final check = await db.customSelect('PRAGMA integrity_check').get();
    final checkResult = check.isEmpty ? '' : '${check.first.data.values.first}';
    if (checkResult != 'ok') {
      throw StateError('Database integrity check failed: $checkResult');
    }

    final createdAt = DateTime.now();
    final dir = await snapshotDirectory();
    final tmp = File(p.join(dir.path, 'snapshot.tmp'));
    if (tmp.existsSync()) tmp.deleteSync();
    // Consistent copy while the app keeps running (PRD I-M6).
    await db.customStatement('VACUUM INTO ?', [tmp.path]);
    final dbBytes = await tmp.readAsBytes();
    await tmp.delete();

    final manifest = BackupManifest(
      appVersion: AppConfig.appVersion,
      schemaVersion: AppDatabase.currentSchemaVersion,
      deviceId: await secure.deviceId(),
      createdAt: createdAt,
      trigger: trigger.name,
      counts: await _counts(),
      sha256: await sha256Hex(dbBytes),
      dbSize: dbBytes.length,
    );
    final bytes = await encodeBackup(
      manifest: manifest,
      keyringJson: Keyring.fromJsonString(keyringJson).toJson(),
      dbBytes: dbBytes,
      masterKey: masterKey,
    );
    final file = File(p.join(dir.path, snapshotName(manifest)));
    await file.writeAsBytes(bytes, flush: true);
    await _pruneLocalSnapshots(dir);
    return LocalSnapshot(file: file, manifest: manifest, bytes: bytes);
  }

  /// Newest local snapshot, if any (for "Download Backup File").
  Future<File?> latestLocalSnapshot() async {
    final files = await _localSnapshotFiles(await snapshotDirectory());
    return files.isEmpty ? null : files.first;
  }

  static String snapshotName(BackupManifest manifest) {
    final t = manifest.createdAt;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}_${two(t.hour)}${two(t.minute)}'
        '${two(t.second)}_v${manifest.schemaVersion}.tkbak';
  }

  static Future<Directory> snapshotDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'backups'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<int>> _masterKey() async {
    final encoded = await secure.read(SecureStore.backupMasterKey);
    if (encoded == null) throw StateError('Backup key missing on this phone');
    return encoded.split(',').map(int.parse).toList();
  }

  /// Reuses the newest local snapshot when nothing changed after it.
  Future<LocalSnapshot> _latestOrNewSnapshot(BackupTrigger trigger) async {
    final latest = await latestLocalSnapshot();
    final dirtySince = await meta.getInt(MetaKeys.dirtySince);
    if (latest != null && dirtySince == null) {
      final bytes = await latest.readAsBytes();
      try {
        final header = readBackupHeader(bytes);
        if (header.manifest.schemaVersion ==
            AppDatabase.currentSchemaVersion) {
          return LocalSnapshot(
            file: latest,
            manifest: header.manifest,
            bytes: bytes,
          );
        }
      } on BackupFormatException {
        // fall through and make a fresh one
      }
    }
    return createLocalSnapshot(trigger);
  }

  Future<Map<String, int>> _counts() async {
    Future<int> count(String table, [String where = '']) async {
      final row = await db
          .customSelect('SELECT COUNT(*) AS c FROM $table $where')
          .getSingle();
      return row.read<int>('c');
    }

    return {
      'workers': await count('workers'),
      'clients': await count('clients'),
      'invoices': await count('documents', "WHERE kind = 'invoice'"),
      'ledgerEntries': await count('ledger_entries'),
      'attendanceDays': await count('attendances'),
    };
  }

  Future<List<File>> _localSnapshotFiles(Directory dir) async {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.tkbak'))
        .toList()
      ..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return files;
  }

  Future<void> _pruneLocalSnapshots(Directory dir) async {
    final files = await _localSnapshotFiles(dir);
    for (final file in files.skip(_localSnapshotsToKeep)) {
      await file.delete();
    }
  }

  Future<String> _rootFolder(DriveStore store) async {
    final cached = await meta.get(MetaKeys.driveRootFolderId);
    if (cached != null) return cached;
    final id = await store.ensureFolder(DriveStore.rootFolderName);
    await meta.set(MetaKeys.driveRootFolderId, id);
    return id;
  }

  Future<String> _dbFolder(DriveStore store, String rootId) async {
    final cached = await meta.get(MetaKeys.driveDbFolderId);
    if (cached != null) return cached;
    final id =
        await store.ensureFolder(DriveStore.dbFolderName, parentId: rootId);
    await meta.set(MetaKeys.driveDbFolderId, id);
    return id;
  }

  /// PRD I-M10: each photo is encrypted and uploaded once, by name.
  Future<void> _uploadPhotos(DriveStore store, String rootId) async {
    final names = await listPhotoNames();
    if (names.isEmpty) return;
    var folderId = await meta.get(MetaKeys.driveFilesFolderId);
    if (folderId == null) {
      folderId =
          await store.ensureFolder(DriveStore.filesFolderName, parentId: rootId);
      await meta.set(MetaKeys.driveFilesFolderId, folderId);
    }
    final remote = {for (final f in await store.listFiles(folderId)) f.name};
    final masterKey = await _masterKey();
    final missing =
        names.where((n) => !remote.contains('$n.enc')).toList();
    for (var i = 0; i < missing.length; i++) {
      final name = missing[i];
      final remoteName = '$name.enc';
      _report(
        'Uploading photos',
        0.9 + 0.1 * i / missing.length,
        '${i + 1} of ${missing.length}',
      );
      final bytes = await (await photoFile(name)).readAsBytes();
      final encrypted = await encryptBlob(bytes, masterKey);
      await _withRetry(() => store.upload(
            folderId: folderId!,
            name: remoteName,
            bytes: encrypted,
          ));
    }
  }

  Future<void> _ensureKeysUploaded(DriveStore store, String rootId) async {
    final keyring = await meta.get(MetaKeys.keyring);
    if (keyring == null) return;
    if (await meta.get(MetaKeys.keyringUploaded) == keyring) return;
    await store.writeJson(
      rootId,
      DriveStore.keysFileName,
      Keyring.fromJsonString(keyring).toJson(),
    );
    await meta.set(MetaKeys.keyringUploaded, keyring);
  }

  /// PRD I-M12: compares the phone clock with Drive's time of the upload
  /// that just finished. Returns "now" by Drive's clock, so retention keeps
  /// the right files even when the phone date is wrong.
  Future<DateTime> _checkClock(DateTime? serverTime) async {
    final phoneNow = DateTime.now();
    if (serverTime == null) return phoneNow;
    final skew = significantClockSkew(server: serverTime, phone: phoneNow);
    if (skew == null) {
      await meta.remove(MetaKeys.clockSkewSeconds);
      return phoneNow;
    }
    await meta.setInt(MetaKeys.clockSkewSeconds, skew.inSeconds);
    return serverTime.toLocal();
  }

  Future<void> _applyRetention(
    DriveStore store,
    String dbFolderId,
    DateTime now,
  ) async {
    try {
      final files = await store.listFiles(dbFolderId);
      final toDelete = backupsToDelete(
        [
          for (final f in files)
            RemoteBackup(id: f.id, createdAt: f.createdTime),
        ],
        now,
      );
      for (final id in toDelete) {
        await store.delete(id);
      }
    } catch (_) {
      // Retention is housekeeping; never fail a good backup because of it.
    }
  }

  Future<T> _withRetry<T>(Future<T> Function() action) async {
    var delay = const Duration(seconds: 2);
    for (var attempt = 1;; attempt++) {
      try {
        return await action().timeout(const Duration(minutes: 3));
      } catch (_) {
        if (attempt >= 3) rethrow;
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
  }

  Future<bool> _acquireLock() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final until = await meta.getInt(MetaKeys.backupLockUntil);
    if (until != null && until > now) return false;
    await meta.setInt(
        MetaKeys.backupLockUntil, now + _lockDuration.inMilliseconds);
    return true;
  }

  Future<BackupResult> _finish(String logId, BackupResult result) async {
    final status = switch (result.outcome) {
      BackupOutcome.success => BackupStatus.success,
      BackupOutcome.skipped || BackupOutcome.notSetUp => BackupStatus.skipped,
      _ => BackupStatus.failed,
    };
    await (db.update(db.backupLogs)..where((l) => l.id.equals(logId))).write(
      BackupLogsCompanion(
        status: Value(status),
        finishedAt: Value(DateTime.now().millisecondsSinceEpoch),
        error: Value(result.message),
      ),
    );
    if (status == BackupStatus.failed) {
      await meta.set(MetaKeys.lastBackupError, result.message ?? 'Failed');
    }
    try {
      await ReminderService(db).onBackupFinished(
        failed: switch (result.outcome) {
          BackupOutcome.success => false,
          BackupOutcome.skipped ||
          BackupOutcome.notSetUp ||
          BackupOutcome.waitingForInternet =>
            null,
          _ => true,
        },
        error: result.message,
      );
    } catch (_) {
      // A notification problem must not change the backup result.
    }
    return result;
  }
}

/// "1.2 MB of 3.4 MB".
String _sizeText(int sent, int total) {
  String mb(int b) => (b / (1024 * 1024)).toStringAsFixed(1);
  return '${mb(sent)} MB of ${mb(total)} MB';
}

/// Master key is kept in secure storage as comma separated bytes.
String encodeMasterKey(List<int> key) => key.join(',');
