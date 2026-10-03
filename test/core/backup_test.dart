import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/core/backup/backup_format.dart';
import 'package:thekedaar/core/backup/backup_scheduler.dart';
import 'package:thekedaar/core/backup/keyring.dart';
import 'package:thekedaar/core/backup/retention.dart';
import 'package:thekedaar/core/db/database.dart';

BackupManifest _manifest(List<int> db, String sha) => BackupManifest(
      appVersion: '0.1.0',
      schemaVersion: 1,
      deviceId: 'device-1',
      createdAt: DateTime(2026, 10, 3, 14),
      trigger: 'manual',
      counts: const {'workers': 3},
      sha256: sha,
      dbSize: db.length,
    );

void main() {
  group('keyring (PRD I-M7, I-M8)', () {
    test('password and recovery key both open the master key', () async {
      final recovery = generateRecoveryKey();
      final created = await Keyring.create(
        password: 'secret123',
        recoveryKey: recovery,
        kdf: KdfParams.testing,
      );
      expect(await created.keyring.unlockWithPassword('secret123'),
          created.masterKey);
      // Lower case, no dashes still works.
      expect(
        await created.keyring.unlockWithRecoveryKey(
            recovery.replaceAll('-', '').toLowerCase()),
        created.masterKey,
      );
      await expectLater(
        created.keyring.unlockWithPassword('wrong-pass'),
        throwsA(isA<WrongSecretException>()),
      );
    });

    test('new password opens the same key, old one does not', () async {
      final recovery = generateRecoveryKey();
      final created = await Keyring.create(
        password: 'old-password',
        recoveryKey: recovery,
        kdf: KdfParams.testing,
      );
      final changed = await Keyring.fromJsonString(
        created.keyring.toJsonString(),
      ).withNewPassword(created.masterKey, 'new-password');
      expect(await changed.unlockWithPassword('new-password'),
          created.masterKey);
      expect(await changed.unlockWithRecoveryKey(recovery), created.masterKey);
      await expectLater(
        changed.unlockWithPassword('old-password'),
        throwsA(isA<WrongSecretException>()),
      );
    });

    test('recovery key format', () {
      final key = generateRecoveryKey();
      expect(key, matches(RegExp(r'^([A-Z2-9]{4}-){5}[A-Z2-9]{4}$')));
      expect(normalizeRecoveryKey('ab-cd ef'), 'ABCDEF');
    });
  });

  group('backup file format', () {
    late ({Keyring keyring, List<int> masterKey}) keys;
    final db = List<int>.generate(5000, (i) => i % 251);

    setUpAll(() async {
      keys = await Keyring.create(
        password: 'secret123',
        recoveryKey: generateRecoveryKey(),
        kdf: KdfParams.testing,
      );
    });

    Future<Uint8List> encode() async => encodeBackup(
          manifest: _manifest(db, await sha256Hex(db)),
          keyringJson: keys.keyring.toJson(),
          dbBytes: db,
          masterKey: keys.masterKey,
        );

    test('round trip', () async {
      final file = await encode();
      final header = readBackupHeader(file);
      expect(header.manifest.deviceId, 'device-1');
      expect(header.manifest.counts['workers'], 3);
      expect(Keyring.fromJson(header.keyringJson).passwordSalt,
          keys.keyring.passwordSalt);
      expect(await decodeBackup(file, keys.masterKey), db);
    });

    test('tampered file is rejected', () async {
      final file = await encode();
      final tampered = Uint8List.fromList(file)..[file.length - 1] ^= 0xff;
      await expectLater(
        decodeBackup(tampered, keys.masterKey),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('wrong key is rejected', () async {
      final file = await encode();
      await expectLater(
        decodeBackup(file, List<int>.filled(32, 7)),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('photo blobs round trip and detect tampering (I-M10)', () async {
      final photo = List<int>.generate(3000, (i) => (i * 7) % 256);
      final enc = await encryptBlob(photo, keys.masterKey);
      expect(await decryptBlob(enc, keys.masterKey), photo);
      final tampered = Uint8List.fromList(enc)..[20] ^= 1;
      await expectLater(
        decryptBlob(tampered, keys.masterKey),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('other files are rejected', () {
      expect(
        () => readBackupHeader(Uint8List.fromList(List.filled(40, 1))),
        throwsA(isA<BackupFormatException>()),
      );
    });
  });

  test('VACUUM INTO snapshot opens and keeps the schema version (I-M6)',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final dir = Directory.systemTemp.createTempSync('tk_snapshot');
    try {
      await db.customSelect('SELECT 1').get(); // open + create schema
      final path = '${dir.path}/snap.db';
      await db.customStatement('VACUUM INTO ?', [path]);
      final bytes = File(path).readAsBytesSync();
      expect(sqliteUserVersion(bytes), AppDatabase.currentSchemaVersion);

      final copy = AppDatabase(NativeDatabase(File(path)));
      final check = await copy.customSelect('PRAGMA integrity_check').get();
      expect(check.first.data.values.first, 'ok');
      await copy.close();
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });

  test('retention keeps recent, daily and monthly backups (PRD D5)', () {
    final now = DateTime(2026, 10, 3, 12);
    RemoteBackup b(String id, DateTime t) => RemoteBackup(id: id, createdAt: t);
    final backups = [
      b('recent1', now.subtract(const Duration(hours: 2))),
      b('recent2', now.subtract(const Duration(days: 1))),
      b('recent3', now.subtract(const Duration(days: 2, hours: 20))),
      b('day-late', DateTime(2026, 9, 20, 22)),
      b('day-mid', DateTime(2026, 9, 20, 14)),
      b('day-early', DateTime(2026, 9, 20, 10)),
      b('month-late', DateTime(2026, 6, 25)),
      b('month-early', DateTime(2026, 6, 5)),
      b('ancient', DateTime(2025, 1, 1)),
    ];
    expect(
      backupsToDelete(backups, now),
      {'day-mid', 'day-early', 'month-early', 'ancient'},
    );
  });

  test('latest backup slot', () {
    const slots = [10, 14, 18, 22];
    expect(latestSlot(slots, DateTime(2026, 10, 3, 15, 30)),
        DateTime(2026, 10, 3, 14));
    expect(latestSlot(slots, DateTime(2026, 10, 3, 8)),
        DateTime(2026, 10, 2, 22));
    expect(latestSlot(const [], DateTime(2026, 10, 3)), isNull);
  });
}
