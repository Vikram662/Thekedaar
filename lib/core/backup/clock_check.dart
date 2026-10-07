import '../i18n/i18n.dart';

/// PRD I-M12: entries are saved with the phone's time. At backup time the
/// phone clock is compared with Google Drive's server time, and a gap of
/// more than [clockSkewLimit] is shown as a warning.
const clockSkewLimit = Duration(minutes: 10);

/// `server - phone`. Positive: the phone is behind.
Duration clockOffset({required DateTime server, required DateTime phone}) =>
    server.toUtc().difference(phone.toUtc());

/// The offset when it is too large to ignore, otherwise null.
Duration? significantClockSkew({
  required DateTime server,
  required DateTime phone,
  Duration limit = clockSkewLimit,
}) {
  final offset = clockOffset(server: server, phone: phone);
  return offset.abs() > limit ? offset : null;
}

/// "2 hours 5 min behind" / "3 days ahead".
String describeClockSkew(Duration offset) {
  final abs = offset.abs();
  final String amount;
  if (abs.inDays >= 1) {
    amount = trPlural(abs.inDays, '1 day', '{count} days');
  } else if (abs.inHours >= 1) {
    final minutes = abs.inMinutes % 60;
    amount = trPlural(abs.inHours, '1 hour', '{count} hours') +
        (minutes == 0 ? '' : tr(' {count} min', {'count': minutes}));
  } else {
    amount = tr('{count} min', {'count': abs.inMinutes});
  }
  return tr(offset.isNegative ? '{amount} ahead' : '{amount} behind',
      {'amount': amount});
}
