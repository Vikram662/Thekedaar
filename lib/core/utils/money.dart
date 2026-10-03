import 'package:intl/intl.dart';

import 'decimal.dart';

final _rupeeFormat =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _rupeePaiseFormat =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// `"600"` → 60000, `"1,250.75"` → 125075. Null if invalid.
int? parseRupeesToPaise(String input) => parseScaled(input, 2);

/// Indian format: 12500000 → `₹1,25,000`, 60050 → `₹600.50`.
/// Paise are shown only when the amount has them (or [alwaysShowPaise]).
String formatPaise(int paise, {bool alwaysShowPaise = false}) {
  final format =
      alwaysShowPaise || paise % 100 != 0 ? _rupeePaiseFormat : _rupeeFormat;
  return format.format(paise / 100);
}

/// Plain rupee text for input fields: 125075 → `"1250.75"`.
String paiseToInputText(int paise) => formatScaled(paise, 2);
