import 'dart:convert';

/// Business rules stored in `BusinessProfile.settingsJson`.
class AppSettings {
  const AppSettings({
    this.monthlyDivisor = 30,
    this.weeklyOffDay,
    this.backupWifiOnly = false,
    this.backupSlots = defaultBackupSlots,
    this.reminders = const ReminderSettings(),
  });

  factory AppSettings.fromJsonString(String json) {
    final map = (jsonDecode(json.isEmpty ? '{}' : json) as Map)
        .cast<String, dynamic>();
    return AppSettings(
      monthlyDivisor: map['monthlyDivisor'] as int? ?? 30,
      weeklyOffDay: map['weeklyOffDay'] as int?,
      backupWifiOnly: map['backupWifiOnly'] as bool? ?? false,
      backupSlots: (map['backupSlots'] as List?)?.cast<int>() ??
          defaultBackupSlots,
      reminders: ReminderSettings.fromJson(
        (map['reminders'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }

  static const defaultBackupSlots = [10, 14, 18, 22];
  static const threeBackupSlots = [10, 16, 22];

  /// PRD I-S1: 30, 26 or 0 (= days in month). Used for new monthly workers.
  final int monthlyDivisor;

  /// `DateTime.monday` … `DateTime.sunday`, or null for no fixed weekly off.
  final int? weeklyOffDay;

  /// PRD D1 step 5: back up only on Wi-Fi.
  final bool backupWifiOnly;

  /// Hours of the day for scheduled backups (PRD D3).
  final List<int> backupSlots;

  /// PRD DB-07: which local notifications to show.
  final ReminderSettings reminders;

  AppSettings copyWith({
    int? monthlyDivisor,
    int? Function()? weeklyOffDay,
    bool? backupWifiOnly,
    List<int>? backupSlots,
    ReminderSettings? reminders,
  }) =>
      AppSettings(
        monthlyDivisor: monthlyDivisor ?? this.monthlyDivisor,
        weeklyOffDay: weeklyOffDay != null ? weeklyOffDay() : this.weeklyOffDay,
        backupWifiOnly: backupWifiOnly ?? this.backupWifiOnly,
        backupSlots: backupSlots ?? this.backupSlots,
        reminders: reminders ?? this.reminders,
      );

  String toJsonString() => jsonEncode({
        'monthlyDivisor': monthlyDivisor,
        if (weeklyOffDay != null) 'weeklyOffDay': weeklyOffDay,
        'backupWifiOnly': backupWifiOnly,
        'backupSlots': backupSlots,
        'reminders': reminders.toJson(),
      });
}

/// On/off switches for each kind of reminder notification. All on by default.
class ReminderSettings {
  const ReminderSettings({
    this.backup = true,
    this.overdueBills = true,
    this.monthEnd = true,
    this.holidays = true,
  });

  factory ReminderSettings.fromJson(Map<String, dynamic> map) =>
      ReminderSettings(
        backup: map['backup'] as bool? ?? true,
        overdueBills: map['overdueBills'] as bool? ?? true,
        monthEnd: map['monthEnd'] as bool? ?? true,
        holidays: map['holidays'] as bool? ?? true,
      );

  /// Backup failed twice, pending over 24 h, or phone clock wrong.
  final bool backup;
  final bool overdueBills;

  /// Last day of the month: settle workers' khata.
  final bool monthEnd;

  /// The day before a holiday.
  final bool holidays;

  ReminderSettings copyWith({
    bool? backup,
    bool? overdueBills,
    bool? monthEnd,
    bool? holidays,
  }) =>
      ReminderSettings(
        backup: backup ?? this.backup,
        overdueBills: overdueBills ?? this.overdueBills,
        monthEnd: monthEnd ?? this.monthEnd,
        holidays: holidays ?? this.holidays,
      );

  Map<String, dynamic> toJson() => {
        'backup': backup,
        'overdueBills': overdueBills,
        'monthEnd': monthEnd,
        'holidays': holidays,
      };
}
