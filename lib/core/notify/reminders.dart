import 'package:drift/drift.dart' show Variable;

import '../backup/clock_check.dart';
import '../db/database.dart';
import '../db/meta_store.dart';
import '../settings/app_settings.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import 'notifications.dart';

class Reminder {
  const Reminder(this.kind, this.title, this.body);

  final NotificationKind kind;
  final String title;
  final String body;
}

/// Everything the reminder rules look at, read from the database.
class ReminderFacts {
  const ReminderFacts({
    this.overdueBills = 0,
    this.overduePaise = 0,
    this.activeWorkers = 0,
    this.holidayTomorrow,
    this.backupConfigured = false,
    this.dirtySince,
    this.clockSkewSeconds,
  });

  final int overdueBills;
  final int overduePaise;
  final int activeWorkers;
  final String? holidayTomorrow;
  final bool backupConfigured;
  final DateTime? dirtySince;
  final int? clockSkewSeconds;
}

/// Reminders are shown between 9 am and 9 pm only.
bool isReminderHour(DateTime now) => now.hour >= 9 && now.hour < 21;

/// PRD DB-07 / D3.1 rules. Pure, so it can be tested.
List<Reminder> computeReminders(
  ReminderFacts f,
  ReminderSettings settings,
  DateTime now,
) {
  final out = <Reminder>[];
  if (settings.backup && f.backupConfigured) {
    final since = f.dirtySince;
    if (since != null && now.difference(since) > const Duration(hours: 24)) {
      out.add(const Reminder(
        NotificationKind.backupPending,
        'Backup pending',
        'Your latest entries are not on Google Drive yet. '
            'Connect to the internet and open the app.',
      ));
    }
    final skew = f.clockSkewSeconds;
    if (skew != null) {
      out.add(Reminder(
        NotificationKind.clockWrong,
        'Phone time is wrong',
        'Your phone clock is '
            '${describeClockSkew(Duration(seconds: skew))}. '
            'Turn on automatic date & time so entries get the right date.',
      ));
    }
  }
  if (settings.overdueBills && f.overdueBills > 0) {
    out.add(Reminder(
      NotificationKind.overdueBills,
      'Payment overdue',
      f.overdueBills == 1
          ? '1 bill is past its due date: ${formatPaise(f.overduePaise)} '
              'to collect. Send a reminder from Lena / Dena.'
          : '${f.overdueBills} bills are past their due date: '
              '${formatPaise(f.overduePaise)} to collect. '
              'Send reminders from Lena / Dena.',
    ));
  }
  final lastDay = DateTime(now.year, now.month + 1, 0).day;
  if (settings.monthEnd && f.activeWorkers > 0 && now.day == lastDay) {
    out.add(const Reminder(
      NotificationKind.monthEnd,
      'Month end',
      'Check attendance and settle workers\' khata for this month.',
    ));
  }
  final holiday = f.holidayTomorrow;
  if (settings.holidays && holiday != null) {
    out.add(Reminder(
      NotificationKind.holiday,
      'Holiday tomorrow',
      '$holiday. Tell your workers.',
    ));
  }
  return out;
}

/// Reads the facts, applies the rules and shows each reminder at most once a
/// day. Called from the hourly background job and when the app opens.
class ReminderService {
  ReminderService(this.db, {AppNotifications? notifications})
      : notifications = notifications ?? AppNotifications.instance;

  final AppDatabase db;
  final AppNotifications notifications;

  MetaStore get _meta => MetaStore(db);

  Future<ReminderSettings> _settings() async {
    final profile = await db.select(db.businessProfiles).getSingleOrNull();
    return AppSettings.fromJsonString(profile?.settingsJson ?? '{}').reminders;
  }

  Future<void> run({DateTime? at}) async {
    final now = at ?? DateTime.now();
    if (!isReminderHour(now)) return;
    final profile = await db.select(db.businessProfiles).getSingleOrNull();
    if (profile == null) return;
    final reminders =
        computeReminders(await readFacts(now), await _settings(), now);
    for (final r in reminders) {
      await showOncePerDay(r, now);
    }
  }

  Future<void> showOncePerDay(Reminder r, DateTime now) async {
    final key = MetaKeys.reminderSent(r.kind.name);
    final today = isoDate(now);
    if (await _meta.get(key) == today) return;
    await notifications.show(r.kind, r.title, r.body);
    await _meta.set(key, today);
  }

  Future<ReminderFacts> readFacts(DateTime now) async {
    final today = isoDate(now);
    final overdue = await db.customSelect(
      '''
      SELECT COUNT(*) AS n, COALESCE(SUM(bal), 0) AS total FROM (
        SELECT d.total_paise - COALESCE((SELECT SUM(p.amount_paise)
            FROM payments_received p WHERE p.document_id = d.id), 0) AS bal
        FROM documents d
        WHERE d.kind = 'invoice'
          AND d.status IN ('sent', 'partiallyPaid')
          AND d.due_date IS NOT NULL AND d.due_date < ?
      ) WHERE bal > 0
      ''',
      variables: [Variable.withString(today)],
    ).getSingle();
    final workers = await db.customSelect(
      'SELECT COUNT(*) AS n FROM workers WHERE is_active = 1',
    ).getSingle();
    final tomorrow = isoDate(DateTime(now.year, now.month, now.day + 1));
    final holiday = await (db.select(db.holidays)
          ..where((h) => h.date.equals(tomorrow)))
        .getSingleOrNull();
    final dirty = await _meta.getInt(MetaKeys.dirtySince);
    return ReminderFacts(
      overdueBills: overdue.read<int>('n'),
      overduePaise: overdue.read<int>('total'),
      activeWorkers: workers.read<int>('n'),
      holidayTomorrow: holiday?.name,
      backupConfigured: await _meta.getBool(MetaKeys.backupConfigured),
      dirtySince:
          dirty == null ? null : DateTime.fromMillisecondsSinceEpoch(dirty),
      clockSkewSeconds: await _meta.getInt(MetaKeys.clockSkewSeconds),
    );
  }

  /// PRD D4: notify after 2 failed backups in a row; clear on success.
  /// "Waiting for internet" is not a failure (it is retried by itself).
  Future<void> onBackupFinished({required bool? failed, String? error}) async {
    if (failed == null) return;
    if (!failed) {
      await _meta.setInt(MetaKeys.consecutiveBackupFailures, 0);
      await notifications.cancel(NotificationKind.backupFailed);
      await notifications.cancel(NotificationKind.backupPending);
      return;
    }
    final count =
        (await _meta.getInt(MetaKeys.consecutiveBackupFailures) ?? 0) + 1;
    await _meta.setInt(MetaKeys.consecutiveBackupFailures, count);
    if (count < 2 || !(await _settings()).backup) return;
    await showOncePerDay(
      Reminder(
        NotificationKind.backupFailed,
        'Backup failed',
        'Google Drive backup failed $count times. '
            '${error == null ? '' : '$error '}Open the app to fix it.',
      ),
      DateTime.now(),
    );
  }
}
