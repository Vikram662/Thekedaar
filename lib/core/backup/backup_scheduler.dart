import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../db/database.dart';
import '../db/enums.dart';
import '../db/meta_store.dart';
import '../settings/app_settings.dart';
import 'backup_engine.dart';

const pendingBackupTask = 'backup-pending';
const scheduledBackupTask = 'backup-scheduled';

/// WorkManager entry point, runs in a background isolate even when the app
/// is closed (PRD D3, D3.1 layer 1).
@pragma('vm:entry-point')
void backupCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    final db = AppDatabase();
    try {
      final engine = BackupEngine(db: db);
      if (task == scheduledBackupTask) {
        final settings = await _settings(db);
        final meta = MetaStore(db);
        final slot = latestSlot(settings.backupSlots, DateTime.now());
        final lastRun = await meta.getInt(MetaKeys.lastSlotRun) ?? 0;
        if (slot == null || slot.millisecondsSinceEpoch <= lastRun) return true;
        await meta.setInt(MetaKeys.lastSlotRun, slot.millisecondsSinceEpoch);
        await engine.run(BackupTrigger.scheduled);
        return true; // the periodic job runs again anyway
      }
      final result = await engine.run(BackupTrigger.onChange);
      return !result.shouldRetry; // false → WorkManager retries with backoff
    } catch (_) {
      return false;
    } finally {
      await db.close();
    }
  });
}

Future<AppSettings> _settings(AppDatabase db) async {
  final profile = await db.select(db.businessProfiles).getSingleOrNull();
  return AppSettings.fromJsonString(profile?.settingsJson ?? '{}');
}

/// Most recent slot time (today or yesterday) that is not in the future.
DateTime? latestSlot(List<int> slotHours, DateTime now) {
  if (slotHours.isEmpty) return null;
  final hours = [...slotHours]..sort();
  for (final hour in hours.reversed) {
    final today = DateTime(now.year, now.month, now.day, hour);
    if (!today.isAfter(now)) return today;
  }
  final yesterday = now.subtract(const Duration(days: 1));
  return DateTime(yesterday.year, yesterday.month, yesterday.day, hours.last);
}

class BackupScheduler {
  static bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await Workmanager().initialize(backupCallbackDispatcher);
    _initialized = true;
  }

  /// One pending upload that Android holds until there is internet, even if
  /// the app is closed (PRD D3.1). KEEP: never more than one in the queue.
  Future<void> schedulePending({
    required bool wifiOnly,
    Duration delay = const Duration(minutes: 2),
  }) async {
    await initialize();
    await Workmanager().registerOneOffTask(
      pendingBackupTask,
      pendingBackupTask,
      initialDelay: delay,
      constraints: Constraints(
        networkType: wifiOnly ? NetworkType.unmetered : NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
  }

  /// Hourly check; the job itself decides if a slot (10/14/18/22) is due.
  Future<void> schedulePeriodic({required bool wifiOnly}) async {
    await initialize();
    await Workmanager().registerPeriodicTask(
      scheduledBackupTask,
      scheduledBackupTask,
      frequency: const Duration(hours: 1),
      constraints: Constraints(
        networkType: wifiOnly ? NetworkType.unmetered : NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  Future<void> cancelAll() async {
    await initialize();
    await Workmanager().cancelAll();
  }
}
