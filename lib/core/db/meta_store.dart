import 'database.dart';

/// Keys used in the `app_meta` table.
abstract final class MetaKeys {
  static const defaultTerms = 'default_terms';

  // Backup state (PRD D3 / D3.1)
  static const backupConfigured = 'backup_configured';
  static const driveEmail = 'drive_email';
  static const keyring = 'backup_keyring';
  static const keyringUploaded = 'backup_keyring_uploaded';
  static const dirtySince = 'dirty_since';
  static const pendingChanges = 'pending_changes';
  static const lastBackupAt = 'last_backup_at';
  static const lastBackupError = 'last_backup_error';
  static const backupBlocked = 'backup_blocked';

  /// Set after a restore: the next backup makes this phone the active one.
  static const claimDevice = 'claim_device';
  static const backupLockUntil = 'backup_lock_until';
  static const lastSlotRun = 'last_slot_run';
  static const driveRootFolderId = 'drive_root_folder_id';
  static const driveDbFolderId = 'drive_db_folder_id';
  static const driveFilesFolderId = 'drive_files_folder_id';

  /// Set after a restore: photos still need to come down from Drive.
  static const photosRestorePending = 'photos_restore_pending';

  /// PRD I-M12: Drive time minus phone time, in seconds, when the gap is
  /// over 10 minutes. Removed once the clock is right again.
  static const clockSkewSeconds = 'clock_skew_seconds';

  // Reminders (PRD DB-07)
  static const consecutiveBackupFailures = 'backup_consecutive_failures';
  static const notificationsAsked = 'notifications_asked';

  /// `reminder_sent_<kind>` → 'yyyy-MM-dd' of the last notification of that
  /// kind, so each reminder shows at most once a day.
  static String reminderSent(String kind) => 'reminder_sent_$kind';
}

/// Small typed wrapper over the `app_meta` key/value table.
class MetaStore {
  MetaStore(this._db);

  final AppDatabase _db;

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.appMeta)
          ..where((m) => m.metaKey.equals(key)))
        .getSingleOrNull();
    return row?.metaValue;
  }

  Future<int?> getInt(String key) async => int.tryParse(await get(key) ?? '');

  Future<bool> getBool(String key) async => (await get(key)) == 'true';

  Future<void> set(String key, String value) => _db
      .into(_db.appMeta)
      .insertOnConflictUpdate(
        AppMetaCompanion.insert(metaKey: key, metaValue: value),
      );

  Future<void> setInt(String key, int value) => set(key, '$value');

  Future<void> setBool(String key, bool value) => set(key, '$value');

  Future<void> remove(String key) =>
      (_db.delete(_db.appMeta)..where((m) => m.metaKey.equals(key))).go();

  /// Emits the value of [key] whenever it changes.
  Stream<String?> watch(String key) => (_db.select(_db.appMeta)
        ..where((m) => m.metaKey.equals(key)))
      .watchSingleOrNull()
      .map((row) => row?.metaValue);

  /// Emits the whole table as a map whenever any key changes.
  Stream<Map<String, String>> watchAll() =>
      _db.select(_db.appMeta).watch().map(
            (rows) => {for (final row in rows) row.metaKey: row.metaValue},
          );
}

extension MetaStoreValue on Map<String, String> {
  int? intValue(String key) => int.tryParse(this[key] ?? '');
  bool boolValue(String key) => this[key] == 'true';
}

