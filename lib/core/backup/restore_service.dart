import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';

import '../db/database.dart';
import '../db/meta_store.dart';
import '../i18n/i18n.dart';
import '../security/secure_store.dart';
import '../utils/photo_store.dart';
import 'backup_engine.dart';
import 'backup_format.dart';
import 'drive_store.dart';
import 'google_drive_auth.dart';
import 'keyring.dart';

class RestoreException implements Exception {
  const RestoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One backup on Drive, for the restore list (PRD D6 step 3).
class DriveBackupInfo {
  const DriveBackupInfo({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.createdAt,
    required this.counts,
    required this.trigger,
  });

  final String id;
  final String name;
  final int sizeBytes;
  final DateTime createdAt;
  final Map<String, int> counts;
  final String? trigger;
}

/// A decrypted, verified backup ready to replace the live database.
class PreparedRestore {
  const PreparedRestore({
    required this.dbBytes,
    required this.manifest,
    required this.masterKey,
    required this.keyring,
  });

  final Uint8List dbBytes;
  final BackupManifest manifest;
  final List<int> masterKey;
  final Keyring keyring;
}

class RestoreService {
  RestoreService({GoogleDriveAuth? auth, SecureStore? secureStore})
      : auth = auth ?? GoogleDriveAuth(),
        secure = secureStore ?? SecureStore();

  final GoogleDriveAuth auth;
  final SecureStore secure;

  Future<DriveStore> _store() async {
    final client = await auth.client(interactive: true);
    if (client == null) {
      throw RestoreException(tr('Please sign in to Google Drive again'));
    }
    return DriveStore(client);
  }

  Future<String> _rootFolder(DriveStore store) async {
    final id = await store.findFolder(DriveStore.rootFolderName);
    if (id == null) {
      throw RestoreException(
        tr('No Thekedaar backups found in this Google account'),
      );
    }
    return id;
  }

  Future<List<DriveBackupInfo>> listDriveBackups() async {
    final store = await _store();
    final rootId = await _rootFolder(store);
    final dbId =
        await store.findFolder(DriveStore.dbFolderName, parentId: rootId);
    if (dbId == null) return const [];
    final files = await store.listFiles(dbId);
    return [
      for (final f in files)
        if (f.name.endsWith('.tkbak'))
          DriveBackupInfo(
            id: f.id,
            name: f.name,
            sizeBytes: f.size,
            createdAt: f.createdTime.toLocal(),
            trigger: f.appProperties['trigger'],
            counts: {
              for (final key in const [
                'workers',
                'clients',
                'invoices',
                'ledgerEntries',
                'attendanceDays',
              ])
                if (int.tryParse(f.appProperties[key] ?? '') != null)
                  key: int.parse(f.appProperties[key]!),
            },
          ),
    ];
  }

  /// Latest keyring from Drive (follows password changes), if present.
  Future<Keyring?> driveKeyring() async {
    final store = await _store();
    final rootId = await _rootFolder(store);
    final json = await store.readJson(rootId, DriveStore.keysFileName);
    return json == null ? null : Keyring.fromJson(json);
  }

  Future<Uint8List> downloadBackup(
    String fileId, {
    void Function(int received, int? total)? onProgress,
  }) async =>
      (await _store()).download(fileId, onProgress: onProgress);

  /// Unlocks with the Backup Password or the Recovery Key, decrypts and
  /// verifies the checksum (PRD D6 steps 4–6). Throws [WrongSecretException],
  /// [BackupFormatException] or [RestoreException].
  Future<PreparedRestore> prepare(
    Uint8List file, {
    String? password,
    String? recoveryKey,
    Keyring? keyring,
  }) async {
    final header = readBackupHeader(file);
    if (header.manifest.schemaVersion > AppDatabase.currentSchemaVersion) {
      throw RestoreException(
        tr('This backup is from a newer app version. Please update the app first.'),
      );
    }
    final ring = keyring ?? Keyring.fromJson(header.keyringJson);
    final List<int> masterKey;
    if (password != null && password.isNotEmpty) {
      masterKey = await _unlockWithPassword(ring, header, password);
    } else if (recoveryKey != null && recoveryKey.isNotEmpty) {
      masterKey = await _unlockWithRecoveryKey(ring, header, recoveryKey);
    } else {
      throw RestoreException(tr('Enter the Backup Password or Recovery Key'));
    }
    final dbBytes = await decodeBackup(file, masterKey);
    return PreparedRestore(
      dbBytes: dbBytes,
      manifest: header.manifest,
      masterKey: masterKey,
      keyring: ring,
    );
  }

  /// The Drive keyring has the newest password; an old file's own keyring
  /// may still have an older one. Try both.
  Future<List<int>> _unlockWithPassword(
    Keyring ring,
    BackupHeader header,
    String password,
  ) async {
    try {
      return await ring.unlockWithPassword(password);
    } on WrongSecretException {
      final fileRing = Keyring.fromJson(header.keyringJson);
      return fileRing.unlockWithPassword(password);
    }
  }

  /// Backup set up again on a reinstall gets a new recovery key, so an
  /// older file may only open with the key from its own keyring.
  Future<List<int>> _unlockWithRecoveryKey(
    Keyring ring,
    BackupHeader header,
    String recoveryKey,
  ) async {
    try {
      return await ring.unlockWithRecoveryKey(recoveryKey);
    } on WrongSecretException {
      final fileRing = Keyring.fromJson(header.keyringJson);
      return fileRing.unlockWithRecoveryKey(recoveryKey);
    }
  }

  /// Writes the restored database next to the live one, checks it opens and
  /// passes `integrity_check` (running migrations for older schemas), keeps
  /// a `.pre_restore` copy of the current data, then swaps the files.
  /// Must be called while the app's database is closed.
  Future<void> writeDatabase(PreparedRestore restore, String dbPath) async {
    final tmp = File('$dbPath.restore');
    await _deleteWithSidecars(tmp.path);
    await tmp.writeAsBytes(restore.dbBytes, flush: true);

    final check = AppDatabase(NativeDatabase(tmp));
    try {
      final rows = await check.customSelect('PRAGMA integrity_check').get();
      final result = rows.isEmpty ? '' : '${rows.first.data.values.first}';
      if (result != 'ok') {
        throw RestoreException(
            tr('Backup database is damaged ({result})', {'result': result}));
      }
    } finally {
      await check.close();
    }

    final current = File(dbPath);
    if (current.existsSync()) {
      await _deleteWithSidecars('$dbPath.pre_restore');
      await current.copy('$dbPath.pre_restore');
    }
    await _deleteWithSidecars(dbPath);
    for (final suffix in ['-wal', '-shm']) {
      final sidecar = File('${tmp.path}$suffix');
      if (sidecar.existsSync()) await sidecar.delete();
    }
    await tmp.rename(dbPath);
  }

  /// Runs on the reopened database: keeps backups going from this phone
  /// and makes it the active device on Drive (PRD D6 step 8, I-M5).
  Future<void> afterRestore(
    AppDatabase db,
    PreparedRestore restore, {
    String? driveEmail,
  }) async {
    final meta = MetaStore(db);
    await secure.write(
        SecureStore.backupMasterKey, encodeMasterKey(restore.masterKey));
    await meta.set(MetaKeys.keyring, restore.keyring.toJsonString());
    if (driveEmail != null) {
      await meta.set(MetaKeys.driveEmail, driveEmail);
      await meta.setBool(MetaKeys.backupConfigured, true);
    }
    await meta.setBool(MetaKeys.claimDevice, true);
    await meta.setBool(MetaKeys.photosRestorePending, true);
    await meta.remove(MetaKeys.backupBlocked);
    await meta.remove(MetaKeys.backupLockUntil);
    await meta.remove(MetaKeys.lastBackupError);
    await meta.remove(MetaKeys.dirtySince);
    await meta.setInt(MetaKeys.pendingChanges, 0);
    await meta.setInt(MetaKeys.lastBackupAt,
        restore.manifest.createdAt.millisecondsSinceEpoch);
  }

  /// Downloads photos missing on this phone (PRD D6 step 7). Returns how
  /// many were restored. Needs the master key in secure storage.
  Future<int> restorePhotos() async {
    final encodedKey = await secure.read(SecureStore.backupMasterKey);
    if (encodedKey == null) return 0;
    final masterKey = encodedKey.split(',').map(int.parse).toList();
    final client = await auth.client();
    if (client == null) throw RestoreException(tr('Drive disconnected'));
    try {
      final store = DriveStore(client);
      final rootId = await store.findFolder(DriveStore.rootFolderName);
      if (rootId == null) return 0;
      final filesId = await store.findFolder(
        DriveStore.filesFolderName,
        parentId: rootId,
      );
      if (filesId == null) return 0;
      final local = (await listPhotoNames()).toSet();
      var restored = 0;
      for (final remote in await store.listFiles(filesId)) {
        if (!remote.name.endsWith('.jpg.enc')) continue;
        final name = remote.name.substring(0, remote.name.length - 4);
        if (local.contains(name)) continue;
        final bytes = await decryptBlob(await store.download(remote.id), masterKey);
        await (await photoFile(name)).writeAsBytes(bytes, flush: true);
        restored++;
      }
      return restored;
    } finally {
      client.close();
    }
  }

  static Future<void> _deleteWithSidecars(String path) async {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final file = File('$path$suffix');
      if (file.existsSync()) await file.delete();
    }
  }
}
