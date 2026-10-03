import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Thrown for files that are not Thekedaar backups or are damaged.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Plain-text description stored in every backup (PRD D4 manifest.json).
class BackupManifest {
  const BackupManifest({
    required this.appVersion,
    required this.schemaVersion,
    required this.deviceId,
    required this.createdAt,
    required this.trigger,
    required this.counts,
    required this.sha256,
    required this.dbSize,
  });

  factory BackupManifest.fromJson(Map<String, dynamic> json) => BackupManifest(
        appVersion: json['appVersion'] as String,
        schemaVersion: json['schemaVersion'] as int,
        deviceId: json['deviceId'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        trigger: json['trigger'] as String,
        counts: (json['counts'] as Map).cast<String, int>(),
        sha256: json['sha256'] as String,
        dbSize: json['dbSize'] as int,
      );

  final String appVersion;
  final int schemaVersion;
  final String deviceId;
  final DateTime createdAt;
  final String trigger;

  /// workers, clients, invoices, ledgerEntries, attendanceDays
  final Map<String, int> counts;

  /// SHA-256 (hex) of the plain database file.
  final String sha256;
  final int dbSize;

  Map<String, dynamic> toJson() => {
        'appVersion': appVersion,
        'schemaVersion': schemaVersion,
        'deviceId': deviceId,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'trigger': trigger,
        'counts': counts,
        'sha256': sha256,
        'dbSize': dbSize,
      };
}

class BackupHeader {
  const BackupHeader({required this.manifest, required this.keyringJson});

  final BackupManifest manifest;

  /// Copy of the keyring at backup time, so a downloaded `.tkbak` file can be
  /// restored without Drive (PRD D6 "Import from File").
  final Map<String, dynamic> keyringJson;
}

// File layout:
//   "TKBAK" | version byte (1) | uint32 BE header length | header JSON (UTF-8)
//   | AES-256-GCM (nonce | ciphertext | mac) of gzip(database file)
// The header bytes are the GCM associated data, so they cannot be altered.
const _magic = [0x54, 0x4B, 0x42, 0x41, 0x4B]; // TKBAK
const _formatVersion = 1;
final _aes = AesGcm.with256bits();

Future<String> sha256Hex(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Future<Uint8List> encodeBackup({
  required BackupManifest manifest,
  required Map<String, dynamic> keyringJson,
  required List<int> dbBytes,
  required List<int> masterKey,
}) async {
  final header = utf8.encode(jsonEncode({
    'manifest': manifest.toJson(),
    'keyring': keyringJson,
  }));
  final box = await _aes.encrypt(
    gzip.encode(dbBytes),
    secretKey: SecretKey(masterKey),
    aad: header,
  );
  final body = box.concatenation();

  final out = BytesBuilder(copy: false)
    ..add(_magic)
    ..addByte(_formatVersion)
    ..add((ByteData(4)..setUint32(0, header.length)).buffer.asUint8List())
    ..add(header)
    ..add(body);
  return out.takeBytes();
}

({BackupHeader header, int bodyOffset, List<int> headerBytes}) _split(
  Uint8List file,
) {
  if (file.length < 10) throw const BackupFormatException('File is too small');
  for (var i = 0; i < _magic.length; i++) {
    if (file[i] != _magic[i]) {
      throw const BackupFormatException('Not a Thekedaar backup file');
    }
  }
  if (file[5] != _formatVersion) {
    throw const BackupFormatException(
      'This backup was made by a newer app. Please update the app.',
    );
  }
  final headerLength = ByteData.sublistView(file, 6, 10).getUint32(0);
  final bodyOffset = 10 + headerLength;
  if (bodyOffset > file.length) {
    throw const BackupFormatException('Backup file is incomplete');
  }
  final headerBytes = file.sublist(10, bodyOffset);
  final json = jsonDecode(utf8.decode(headerBytes)) as Map<String, dynamic>;
  return (
    header: BackupHeader(
      manifest: BackupManifest.fromJson(
        (json['manifest'] as Map).cast<String, dynamic>(),
      ),
      keyringJson: (json['keyring'] as Map).cast<String, dynamic>(),
    ),
    bodyOffset: bodyOffset,
    headerBytes: headerBytes,
  );
}

/// Reads the manifest and keyring without decrypting anything.
BackupHeader readBackupHeader(Uint8List file) => _split(file).header;

/// Decrypts and verifies a backup, returning the plain database bytes.
/// Throws [BackupFormatException] if the file was altered or is corrupt.
Future<Uint8List> decodeBackup(Uint8List file, List<int> masterKey) async {
  final parts = _split(file);
  final box = SecretBox.fromConcatenation(
    file.sublist(parts.bodyOffset),
    nonceLength: _aes.nonceLength,
    macLength: _aes.macAlgorithm.macLength,
  );
  final List<int> compressed;
  try {
    compressed = await _aes.decrypt(
      box,
      secretKey: SecretKey(masterKey),
      aad: parts.headerBytes,
    );
  } on SecretBoxAuthenticationError {
    throw const BackupFormatException(
      'Backup is damaged or was made with a different backup key',
    );
  }
  final dbBytes = Uint8List.fromList(gzip.decode(compressed));
  if (await sha256Hex(dbBytes) != parts.header.manifest.sha256) {
    throw const BackupFormatException('Backup checksum does not match');
  }
  return dbBytes;
}

/// `PRAGMA user_version` straight from the SQLite file header (offset 60).
int sqliteUserVersion(List<int> dbBytes) {
  if (dbBytes.length < 64) return 0;
  return ByteData.sublistView(Uint8List.fromList(dbBytes.sublist(60, 64)))
      .getUint32(0);
}
