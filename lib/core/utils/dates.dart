/// Calendar dates are stored as `yyyy-MM-dd` text (PRD Part F).
library;

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String isoDate(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

DateTime parseIsoDate(String value) {
  final parts = value.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

int daysInMonth(DateTime value) => DateTime(value.year, value.month + 1, 0).day;

/// Indian financial year label: 3 Oct 2026 → `26-27`, 15 Feb 2027 → `26-27`.
String financialYearLabel(DateTime date) {
  final startYear = date.month >= 4 ? date.year : date.year - 1;
  String twoDigits(int year) => (year % 100).toString().padLeft(2, '0');
  return '${twoDigits(startYear)}-${twoDigits(startYear + 1)}';
}

/// `INV/26-27/0001` style number, PRD BL-10.
String documentNumber(String prefix, DateTime date, int sequence) =>
    '$prefix/${financialYearLabel(date)}/${sequence.toString().padLeft(4, '0')}';
