import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Kinds of local notification (PRD DB-07, D3.1, D4). Each has a fixed id,
/// so a newer one replaces the older one instead of piling up.
enum NotificationKind {
  backupFailed(1, 'backup', 'Backup'),
  backupPending(2, 'backup', 'Backup'),
  clockWrong(3, 'backup', 'Backup'),
  overdueBills(4, 'payments', 'Payment reminders'),
  monthEnd(5, 'khata', 'Khata reminders'),
  holiday(6, 'khata', 'Khata reminders'),
  backupProgress(7, 'backup_progress', 'Backup progress');

  const NotificationKind(this.id, this.channelId, this.channelName);

  final int id;
  final String channelId;
  final String channelName;
}

/// Thin wrapper over flutter_local_notifications. Works in the app and in
/// the WorkManager background isolate; failures never break the caller.
class AppNotifications {
  AppNotifications._();

  static final instance = AppNotifications._();

  FlutterLocalNotificationsPlugin? _plugin;
  bool _ready = false;

  /// Kind of the notification the user tapped (app open or opened by it).
  /// The app listens and opens the matching screen.
  final tapped = ValueNotifier<NotificationKind?>(null);

  void _onTap(NotificationResponse response) {
    final kind = NotificationKind.values
        .where((k) => k.name == response.payload)
        .firstOrNull;
    if (kind != null) {
      // Reset first so tapping the same kind twice still notifies.
      tapped.value = null;
      tapped.value = kind;
    }
  }

  FlutterLocalNotificationsPlugin get _p => _plugin!;

  /// Android only; elsewhere (unit tests on the CI machine) it is a no-op.
  Future<bool> _init() async {
    if (_ready) return true;
    if (!Platform.isAndroid) return false;
    try {
      _plugin ??= FlutterLocalNotificationsPlugin();
      await _p.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: _onTap,
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
    return _ready;
  }

  /// Call once when the app starts: if a notification tap launched the
  /// app, [tapped] gets its kind.
  Future<void> initForApp() async {
    if (!await _init()) return;
    try {
      final launch = await _p.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
        _onTap(response);
      }
    } catch (_) {}
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _p.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Android 13+ asks the user once. Call from the app, not the background.
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      return await _android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> enabled() async {
    if (!await _init()) return false;
    try {
      return await _android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<void> show(NotificationKind kind, String title, String body) async {
    if (!await _init()) return;
    try {
      await _p.show(
        kind.id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            kind.channelId,
            kind.channelName,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
        payload: kind.name,
      );
    } catch (e) {
      debugPrint('Notification failed: $e');
    }
  }

  /// Silent ongoing notification with a progress bar while a background
  /// backup uploads (app closed).
  Future<void> showBackupProgress(int percent, String step) async {
    if (!await _init()) return;
    const kind = NotificationKind.backupProgress;
    try {
      await _p.show(
        kind.id,
        'Backing up to Google Drive · $percent%',
        step,
        NotificationDetails(
          android: AndroidNotificationDetails(
            kind.channelId,
            kind.channelName,
            importance: Importance.low,
            priority: Priority.low,
            showProgress: true,
            maxProgress: 100,
            progress: percent,
            onlyAlertOnce: true,
            ongoing: true,
            autoCancel: false,
          ),
        ),
        payload: kind.name,
      );
    } catch (_) {}
  }

  Future<void> cancel(NotificationKind kind) async {
    if (!await _init()) return;
    try {
      await _p.cancel(kind.id);
    } catch (_) {}
  }
}
