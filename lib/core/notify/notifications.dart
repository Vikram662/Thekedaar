import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../i18n/i18n.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Kinds of local notification (PRD DB-07, D3.1, D4). Each has a fixed id,
/// so a newer one replaces the older one instead of piling up.
enum NotificationKind {
  backupFailed(1, 'backup', 'Backup'),
  backupPending(2, 'backup', 'Backup'),
  clockWrong(3, 'backup', 'Backup'),
  overdueBills(4, 'payments', 'Payment reminders'),
  monthEnd(5, 'khata', 'Khata reminders'),
  holiday(6, 'khata', 'Khata reminders'),
  backupProgress(7, 'backup_progress', 'Backup progress'),
  taskReminder(8, 'tasks', 'Tasks & Site Visits');

  const NotificationKind(this.id, this.channelId, this._channelName);

  final int id;
  final String channelId;
  final String _channelName;

  /// Shown in the phone's notification settings.
  String get channelName => tr(_channelName);
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
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
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
        tr('Backing up to Google Drive · {percent}%', {'percent': percent}),
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

  /// Schedules the one-hour warning, the event alarm, and optional same-day
  /// repeats. A task owns a deterministic block of notification IDs so every
  /// future alarm can be cancelled when it is edited, switched off or done.
  Future<void> scheduleTaskNotifications({
    required String taskId,
    required String title,
    required String body,
    required DateTime scheduledAt,
    int? intervalMinutes,
  }) async {
    if (!await _init()) return;
    await cancelTaskNotifications(taskId);

    final now = DateTime.now();
    final times = <DateTime>[];
    final lead = scheduledAt.subtract(const Duration(hours: 1));
    if (lead.isAfter(now)) times.add(lead);
    if (scheduledAt.isAfter(now)) times.add(scheduledAt);

    final interval = intervalMinutes ?? 0;
    if (interval > 0) {
      final endOfDay = DateTime(
        scheduledAt.year,
        scheduledAt.month,
        scheduledAt.day,
        23,
        59,
        59,
      );
      var next = scheduledAt.add(Duration(minutes: interval));
      while (next.isBefore(endOfDay) && times.length < _taskAlarmSlots) {
        if (next.isAfter(now)) times.add(next);
        next = next.add(Duration(minutes: interval));
      }
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        NotificationKind.taskReminder.channelId,
        NotificationKind.taskReminder.channelName,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(body),
      ),
    );
    for (var i = 0; i < times.length; i++) {
      try {
        await _p.zonedSchedule(
          _taskNotificationId(taskId, i),
          title,
          body,
          tz.TZDateTime.from(times[i], tz.local),
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: NotificationKind.taskReminder.name,
        );
      } catch (error) {
        // Some phones deny exact-alarm access. Keep the reminder useful with
        // an inexact offline alarm instead of silently losing it.
        try {
          await _p.zonedSchedule(
            _taskNotificationId(taskId, i),
            title,
            body,
            tz.TZDateTime.from(times[i], tz.local),
            details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: NotificationKind.taskReminder.name,
          );
        } catch (fallbackError) {
          debugPrint('Task alarm scheduling failed: $fallbackError');
        }
      }
    }
  }

  Future<void> cancelTaskNotifications(String taskId) async {
    if (!await _init()) return;
    for (var i = 0; i < _taskAlarmSlots; i++) {
      try {
        await _p.cancel(_taskNotificationId(taskId, i));
      } catch (_) {}
    }
  }

  static const _taskAlarmSlots = 32;

  static int _taskNotificationId(String value, int slot) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return 1000 + (hash % 50000) * _taskAlarmSlots + slot;
  }

  Future<void> cancelId(int id) async {
    if (!await _init()) return;
    try {
      await _p.cancel(id);
    } catch (_) {}
  }
}
