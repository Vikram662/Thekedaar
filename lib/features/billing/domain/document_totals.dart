import '../../../core/db/enums.dart';
import '../../../core/utils/decimal.dart';
import '../../../core/utils/measurement.dart';
import '../../../core/utils/qty.dart';

/// One bill line while editing (PRD BL-03).
class DraftLine {
  const DraftLine({
    required this.lineType,
    required this.name,
    required this.qtyMilli,
    required this.ratePaise,
    this.itemId,
    this.unitId,
    this.unitCode,
    this.measurement = const [],
  });

  final LineType lineType;
  final String name;
  final int qtyMilli;
  final int ratePaise;
  final String? itemId;
  final String? unitId;
  final String? unitCode;

  /// Measurement rows that produced [qtyMilli] (PRD BL-16), may be empty.
  final List<MeasurementEntry> measurement;

  int get amountPaise => lineAmountPaise(qtyMilli, ratePaise);

  DraftLine copyWith({
    LineType? lineType,
    String? name,
    int? qtyMilli,
    int? ratePaise,
    String? itemId,
    String? unitId,
    String? unitCode,
    List<MeasurementEntry>? measurement,
  }) =>
      DraftLine(
        lineType: lineType ?? this.lineType,
        name: name ?? this.name,
        qtyMilli: qtyMilli ?? this.qtyMilli,
        ratePaise: ratePaise ?? this.ratePaise,
        itemId: itemId ?? this.itemId,
        unitId: unitId ?? this.unitId,
        unitCode: unitCode ?? this.unitCode,
        measurement: measurement ?? this.measurement,
      );
}

class DocumentTotals {
  const DocumentTotals({
    required this.subtotalPaise,
    required this.discountPaise,
    required this.roundOffPaise,
  });

  final int subtotalPaise;
  final int discountPaise;
  final int roundOffPaise;

  int get totalPaise => subtotalPaise - discountPaise + roundOffPaise;
}

/// PRD BL-05: discount in ₹ or %, then round off to the nearest rupee.
DocumentTotals computeTotals(
  Iterable<int> lineAmounts, {
  int? discountPercentBp,
  int discountPaise = 0,
  bool roundOff = true,
}) {
  final subtotal = lineAmounts.fold(0, (sum, a) => sum + a);
  var discount = discountPercentBp != null
      ? roundDiv(subtotal * discountPercentBp, 10000)
      : discountPaise;
  discount = discount.clamp(0, subtotal < 0 ? 0 : subtotal);
  final net = subtotal - discount;
  final roundOffPaise = roundOff ? roundDiv(net, 100) * 100 - net : 0;
  return DocumentTotals(
    subtotalPaise: subtotal,
    discountPaise: discount,
    roundOffPaise: roundOffPaise,
  );
}

/// Next sequence number for `PREFIX/26-27/0007` style numbers (PRD BL-10).
int nextSequence(Iterable<String> existingNumbers, String prefixWithYear) {
  var max = 0;
  for (final number in existingNumbers) {
    if (!number.startsWith(prefixWithYear)) continue;
    final seq = int.tryParse(number.substring(prefixWithYear.length));
    if (seq != null && seq > max) max = seq;
  }
  return max + 1;
}

/// Invoice status from payments (PRD BL-13).
DocumentStatus statusAfterPayments(
  DocumentStatus current,
  int totalPaise,
  int paidPaise,
) {
  if (current == DocumentStatus.cancelled) return current;
  if (paidPaise >= totalPaise && totalPaise > 0) return DocumentStatus.paid;
  if (paidPaise > 0) return DocumentStatus.partiallyPaid;
  return current == DocumentStatus.paid ||
          current == DocumentStatus.partiallyPaid
      ? DocumentStatus.sent
      : current;
}
