import 'dart:convert';

/// Business rules stored in `BusinessProfile.settingsJson`.
class AppSettings {
  const AppSettings({
    this.monthlyDivisor = 30,
    this.weeklyOffDay,
    this.backupWifiOnly = false,
    this.backupSlots = defaultBackupSlots,
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

  AppSettings copyWith({
    int? monthlyDivisor,
    int? Function()? weeklyOffDay,
    bool? backupWifiOnly,
    List<int>? backupSlots,
  }) =>
      AppSettings(
        monthlyDivisor: monthlyDivisor ?? this.monthlyDivisor,
        weeklyOffDay: weeklyOffDay != null ? weeklyOffDay() : this.weeklyOffDay,
        backupWifiOnly: backupWifiOnly ?? this.backupWifiOnly,
        backupSlots: backupSlots ?? this.backupSlots,
      );

  String toJsonString() => jsonEncode({
        'monthlyDivisor': monthlyDivisor,
        if (weeklyOffDay != null) 'weeklyOffDay': weeklyOffDay,
        'backupWifiOnly': backupWifiOnly,
        'backupSlots': backupSlots,
      });
}
