import 'decimal.dart';
import 'qty.dart';

/// One row of a measurement (naap) sheet, PRD BL-16.
///
/// Dimensions are milli-units of the line's unit (feet or meters).
/// Give only the dimensions that apply: L for running ft, L × W (or L × H)
/// for area, L × W × H for volume. [isDeduction] rows (doors, windows) are
/// subtracted from the total.
class MeasurementEntry {
  const MeasurementEntry({
    this.label = '',
    this.nos = 1,
    required this.lengthMilli,
    this.widthMilli,
    this.heightMilli,
    this.isDeduction = false,
  });

  factory MeasurementEntry.fromJson(Map<String, dynamic> json) =>
      MeasurementEntry(
        label: json['label'] as String? ?? '',
        nos: json['nos'] as int? ?? 1,
        lengthMilli: json['l'] as int,
        widthMilli: json['w'] as int?,
        heightMilli: json['h'] as int?,
        isDeduction: json['deduct'] as bool? ?? false,
      );

  final String label;
  final int nos;
  final int lengthMilli;
  final int? widthMilli;
  final int? heightMilli;
  final bool isDeduction;

  /// nos × L × W × H in milli-units of the resulting unit.
  int get qtyMilli {
    var value = nos * lengthMilli;
    for (final dimension in [widthMilli, heightMilli]) {
      if (dimension != null) value = roundDiv(value * dimension, milliPerUnit);
    }
    return value;
  }

  Map<String, dynamic> toJson() => {
        if (label.isNotEmpty) 'label': label,
        'nos': nos,
        'l': lengthMilli,
        if (widthMilli != null) 'w': widthMilli,
        if (heightMilli != null) 'h': heightMilli,
        if (isDeduction) 'deduct': true,
      };
}

/// Sum of all entries minus deductions, in milli-units.
int measurementTotalMilli(Iterable<MeasurementEntry> entries) =>
    entries.fold(
      0,
      (sum, e) => e.isDeduction ? sum - e.qtyMilli : sum + e.qtyMilli,
    );
