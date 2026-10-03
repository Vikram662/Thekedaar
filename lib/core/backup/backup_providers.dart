import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../db/enums.dart';
import '../db/meta_store.dart';
import '../db/providers.dart';
import '../security/secure_store.dart';
import '../settings/settings_providers.dart';
import 'backup_engine.dart';
import 'backup_scheduler.dart';
import 'google_drive_auth.dart';
import 'restore_service.dart';

final googleDriveAuthProvider = Provider((ref) => GoogleDriveAuth());
final backupSchedulerProvider = Provider((ref) => BackupScheduler());

final backupEngineProvider = Provider<BackupEngine>(
  (ref) => BackupEngine(
    db: ref.watch(databaseProvider),
    secureStore: ref.watch(secureStoreProvider),
    auth: ref.watch(googleDriveAuthProvider),
  ),
);

/// Dashboard dot (PRD D3.1): green synced, amber pending, red failed/old.
enum BackupHealth { notSetUp, synced, pending, failed }

class BackupState {
  const BackupState({
    required this.configured,
    required this.email,
    required this.lastBackupAt,
    required this.pendingChanges,
    required this.dirtySince,
    required this.lastError,
    required this.blocked,
  });

  final bool configured;
  final String? email;
  final DateTime? lastBackupAt;
  final int pendingChanges;
  final DateTime? dirtySince;
  final String? lastError;
  final bool blocked;

  BackupHealth get health {
    if (!configured) return BackupHealth.notSetUp;
    final last = lastBackupAt;
    final stale = last == null ||
        DateTime.now().difference(last) > const Duration(hours: 24);
    if (blocked || lastError != null && dirtySince != null || stale) {
      return BackupHealth.failed;
    }
    if (dirtySince != null) return BackupHealth.pending;
    return BackupHealth.synced;
  }

  /// PRD D3.1: pending for more than 24 hours.
  bool get pendingTooLong =>
      dirtySince != null &&
      DateTime.now().difference(dirtySince!) > const Duration(hours: 24);
}

final backupStateProvider = StreamProvider<BackupState>((ref) {
  final meta = MetaStore(ref.watch(databaseProvider));
  return meta.watchAll().map((m) {
    DateTime? time(String key) {
      final ms = m.intValue(key);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    }

    return BackupState(
      configured: m.boolValue(MetaKeys.backupConfigured),
      email: m[MetaKeys.driveEmail],
      lastBackupAt: time(MetaKeys.lastBackupAt),
      pendingChanges: m.intValue(MetaKeys.pendingChanges) ?? 0,
      dirtySince: time(MetaKeys.dirtySince),
      lastError: m[MetaKeys.lastBackupError],
      blocked: m.boolValue(MetaKeys.backupBlocked),
    );
  });
});

final backupHistoryProvider = StreamProvider<List<BackupLog>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.backupLogs)
        ..orderBy([(l) => OrderingTerm.desc(l.startedAt)])
        ..limit(30))
      .watch();
});

final backupRunningProvider = StateProvider<bool>((ref) => false);

/// Starts the foreground side of auto backup for the life of the app scope.
final backupCoordinatorProvider = Provider<BackupCoordinator>((ref) {
  final coordinator = BackupCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// Foreground backup triggers (PRD D3, D3.1 layers 2–3, I-M2, I-M4):
/// - data changed → mark dirty, local snapshot, queue a pending upload
/// - app goes to background with changes → upload in ~2 minutes
/// - internet comes back while the app is open → upload now
/// - app opened and last backup older than 24 h, or changes pending → try now
class BackupCoordinator with WidgetsBindingObserver {
  BackupCoordinator(this._ref);

  final Ref _ref;
  StreamSubscription<Object?>? _tableSub;
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  Timer? _markDirtyTimer;
  Timer? _snapshotTimer;
  bool _started = false;

  static const _ignoredTables = {'app_meta', 'backup_logs'};

  AppDatabase get _db => _ref.read(databaseProvider);
  BackupEngine get _engine => _ref.read(backupEngineProvider);
  MetaStore get _meta => MetaStore(_db);

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _tableSub = _db.tableUpdates().listen((updates) {
      if (updates.every((u) => _ignoredTables.contains(u.table))) return;
      _markDirtyTimer?.cancel();
      _markDirtyTimer = Timer(const Duration(seconds: 3), _onDataChanged);
    });
    _netSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(_runIfPending());
      }
    });
    unawaited(_onAppOpened());
  }

  Future<void> _onDataChanged() async {
    if (!await _engine.isSetUp()) return;
    if (await _meta.getInt(MetaKeys.dirtySince) == null) {
      await _meta.setInt(
          MetaKeys.dirtySince, DateTime.now().millisecondsSinceEpoch);
    }
    await _meta.setInt(
      MetaKeys.pendingChanges,
      (await _meta.getInt(MetaKeys.pendingChanges) ?? 0) + 1,
    );
    await _schedulePending();
    _snapshotTimer?.cancel();
    _snapshotTimer = Timer(const Duration(seconds: 60), () async {
      try {
        await _engine.createLocalSnapshot(BackupTrigger.onChange);
      } catch (_) {
        // Next backup run makes a fresh snapshot anyway.
      }
    });
  }

  Future<void> _schedulePending({Duration? delay}) async {
    final settings = await _ref.read(appSettingsProvider.future);
    try {
      await _ref.read(backupSchedulerProvider).schedulePending(
            wifiOnly: settings.backupWifiOnly,
            delay: delay ?? const Duration(minutes: 2),
          );
    } catch (_) {
      // WorkManager unavailable (tests); foreground triggers still work.
    }
  }

  Future<void> _onAppOpened() async {
    if (!await _engine.isSetUp()) return;
    if (await _meta.getBool(MetaKeys.photosRestorePending)) {
      try {
        await RestoreService(
          auth: _ref.read(googleDriveAuthProvider),
          secureStore: _ref.read(secureStoreProvider),
        ).restorePhotos();
        await _meta.remove(MetaKeys.photosRestorePending);
      } catch (_) {
        // Retried the next time the app opens.
      }
    }
    final settings = await _ref.read(appSettingsProvider.future);
    try {
      await _ref
          .read(backupSchedulerProvider)
          .schedulePeriodic(wifiOnly: settings.backupWifiOnly);
    } catch (_) {}
    final last = await _meta.getInt(MetaKeys.lastBackupAt);
    final stale = last == null ||
        DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(last)) >
            const Duration(hours: 24);
    final dirty = await _meta.getInt(MetaKeys.dirtySince) != null;
    if (stale || dirty) await runNow(BackupTrigger.onChange, quiet: true);
  }

  Future<void> _runIfPending() async {
    if (await _meta.getInt(MetaKeys.dirtySince) == null) return;
    await runNow(BackupTrigger.internetBack, quiet: true);
  }

  /// Runs a backup in the app. [quiet] runs are skipped while another runs.
  Future<BackupResult> runNow(
    BackupTrigger trigger, {
    bool quiet = false,
  }) async {
    final running = _ref.read(backupRunningProvider.notifier);
    if (running.state && quiet) {
      return const BackupResult(BackupOutcome.skipped, 'Already running');
    }
    running.state = true;
    try {
      final result = await _engine.run(
        trigger,
        force: trigger == BackupTrigger.manual,
      );
      if (result.outcome == BackupOutcome.waitingForInternet) {
        await _schedulePending(delay: Duration.zero);
      }
      return result;
    } finally {
      running.state = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(() async {
        if (await _meta.getInt(MetaKeys.dirtySince) != null) {
          await _schedulePending();
        }
      }());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_runIfPending());
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tableSub?.cancel();
    _netSub?.cancel();
    _markDirtyTimer?.cancel();
    _snapshotTimer?.cancel();
  }
}
