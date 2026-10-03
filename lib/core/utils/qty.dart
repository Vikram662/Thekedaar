import 'decimal.dart';

/// Quantities are stored as integer milli-units: 12.5 m = 12500 (PRD I-S6).
const int milliPerUnit = 1000;

/// `"12.5"` → 12500. Null if invalid or more than 3 decimals.
int? parseQtyToMilli(String input) => parseScaled(input, 3);

/// 12500 → `"12.5"`, 3000 → `"3"`.
String formatMilli(int milli) => formatScaled(milli, 3);

/// Line amount in paise for [qtyMilli] × [ratePaise], rounded to the nearest paisa.
int lineAmountPaise(int qtyMilli, int ratePaise) =>
    roundDiv(qtyMilli * ratePaise, milliPerUnit);
