/// A backup file stored on Drive.
class RemoteBackup {
  const RemoteBackup({required this.id, required this.createdAt});

  final String id;
  final DateTime createdAt;
}

/// PRD D5 retention. Returns the ids to delete:
/// - keep everything from the last 3 days
/// - for the 30 days before that, the last backup of each day
/// - for the 12 months before that, the last backup of each month
/// - delete the rest (the newest backup is always kept)
Set<String> backupsToDelete(List<RemoteBackup> backups, DateTime now) {
  final sorted = [...backups]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final keepDays = <String>{};
  final keepMonths = <String>{};
  final delete = <String>{};

  for (var i = 0; i < sorted.length; i++) {
    final backup = sorted[i];
    if (i == 0) continue; // newest
    final local = backup.createdAt.toLocal();
    final age = now.difference(backup.createdAt);
    if (age <= const Duration(days: 3)) continue;

    if (age <= const Duration(days: 33)) {
      final day = '${local.year}-${local.month}-${local.day}';
      if (keepDays.add(day)) continue;
    } else if (age <= const Duration(days: 33 + 365)) {
      final month = '${local.year}-${local.month}';
      if (keepMonths.add(month)) continue;
    }
    delete.add(backup.id);
  }
  return delete;
}
