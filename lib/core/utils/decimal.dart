/// Integer-only decimal helpers. Money and quantities never touch `double`
/// (PRD I-S6): rupees are stored as paise, quantities as milli-units.
library;

final _stripChars = RegExp(r'[,\s₹]');
final _decimalPattern = RegExp(r'^(\d*)(?:\.(\d*))?$');

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}

/// Parses user input like `"1,250.75"` into an integer scaled by 10^[scale]
/// (`scale` 2 → 125075). Returns null for invalid input or when the input has
/// more fraction digits than [scale] allows.
int? parseScaled(String input, int scale) {
  var text = input.replaceAll(_stripChars, '');
  var negative = false;
  if (text.startsWith('-')) {
    negative = true;
    text = text.substring(1);
  }
  final match = _decimalPattern.firstMatch(text);
  if (match == null) return null;

  final whole = match.group(1)!;
  final fraction = match.group(2) ?? '';
  if (whole.isEmpty && fraction.isEmpty) return null;
  if (fraction.length > scale) return null;
  if (whole.length > 12) return null; // guard against int overflow

  final wholeValue = whole.isEmpty ? 0 : int.parse(whole);
  final fractionValue =
      scale == 0 ? 0 : int.parse(fraction.padRight(scale, '0'));
  final value = wholeValue * _pow10(scale) + fractionValue;
  return negative ? -value : value;
}

/// Formats a scaled integer back to text: `formatScaled(12500, 3)` → `"12.5"`.
/// Trailing fraction zeros are dropped.
String formatScaled(int value, int scale) {
  final factor = _pow10(scale);
  final sign = value < 0 ? '-' : '';
  final abs = value.abs();
  final whole = abs ~/ factor;
  var fraction = (abs % factor).toString().padLeft(scale, '0');
  fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$sign$whole' : '$sign$whole.$fraction';
}

/// Integer division rounded half away from zero. [denominator] must be > 0.
int roundDiv(int numerator, int denominator) {
  assert(denominator > 0, 'denominator must be positive');
  final half = denominator ~/ 2;
  return numerator >= 0
      ? (numerator + half) ~/ denominator
      : -((-numerator + half) ~/ denominator);
}
