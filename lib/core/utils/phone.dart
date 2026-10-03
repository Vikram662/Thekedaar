final _nonDigits = RegExp(r'\D');
final _indianMobile = RegExp(r'^[6-9]\d{9}$');

/// Normalizes an Indian mobile number to E.164 (`+919876543210`), PRD I-B7.
/// Accepts `98765 43210`, `09876543210`, `+91-98765-43210`.
/// Returns null for empty or invalid input.
String? normalizeIndianPhone(String input) {
  var digits = input.replaceAll(_nonDigits, '');
  if (digits.length == 12 && digits.startsWith('91')) {
    digits = digits.substring(2);
  } else if (digits.length == 11 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  if (!_indianMobile.hasMatch(digits)) return null;
  return '+91$digits';
}

/// `+919876543210` → `98765 43210` for display.
String formatIndianPhone(String e164) {
  final local = e164.startsWith('+91') ? e164.substring(3) : e164;
  if (local.length != 10) return e164;
  return '${local.substring(0, 5)} ${local.substring(5)}';
}
