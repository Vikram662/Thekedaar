import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/ids.dart';

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

/// Secrets that must never be inside the backed-up database (PRD Part F):
/// PIN hash, backup master key, device id.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const pinHash = 'pin_hash';
  static const pinSalt = 'pin_salt';
  static const pinFailures = 'pin_failures';
  static const pinLockedUntil = 'pin_locked_until';
  static const biometricEnabled = 'biometric_enabled';
  static const backupMasterKey = 'backup_master_key';
  static const deviceIdKey = 'device_id';

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<void> delete(String key) => _storage.delete(key: key);

  /// Stable per-install id; not in the DB so a restore cannot copy it
  /// from the old phone (PRD I-M5).
  Future<String> deviceId() async {
    final existing = await read(deviceIdKey);
    if (existing != null) return existing;
    final id = newId();
    await write(deviceIdKey, id);
    return id;
  }
}
