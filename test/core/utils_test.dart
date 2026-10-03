import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/core/utils/dates.dart';
import 'package:thekedaar/core/utils/decimal.dart';
import 'package:thekedaar/core/utils/ids.dart';
import 'package:thekedaar/core/utils/measurement.dart';
import 'package:thekedaar/core/utils/money.dart';
import 'package:thekedaar/core/utils/phone.dart';
import 'package:thekedaar/core/utils/qty.dart';

void main() {
  group('money', () {
    test('parses rupees to paise without floating point', () {
      expect(parseRupeesToPaise('600'), 60000);
      expect(parseRupeesToPaise('1,250.75'), 125075);
      expect(parseRupeesToPaise('₹ 12.5'), 1250);
      expect(parseRupeesToPaise('0.1'), 10);
      expect(parseRupeesToPaise('12.345'), isNull);
      expect(parseRupeesToPaise('abc'), isNull);
      expect(parseRupeesToPaise(''), isNull);
      expect(parseRupeesToPaise('.'), isNull);
    });

    test('formats in Indian grouping', () {
      expect(formatPaise(12500000), '₹1,25,000');
      expect(formatPaise(60050), '₹600.50');
      expect(formatPaise(0), '₹0');
    });

    test('paise to input text', () {
      expect(paiseToInputText(125075), '1250.75');
      expect(paiseToInputText(60000), '600');
      expect(paiseToInputText(1250), '12.5');
    });
  });

  group('qty', () {
    test('parse and format milli-units', () {
      expect(parseQtyToMilli('12.5'), 12500);
      expect(parseQtyToMilli('3'), 3000);
      expect(parseQtyToMilli('0.001'), 1);
      expect(parseQtyToMilli('1.0001'), isNull);
      expect(formatMilli(12500), '12.5');
      expect(formatMilli(3000), '3');
      expect(formatMilli(-1500), '-1.5');
    });

    test('line amount rounds to nearest paisa', () {
      // 12.5 sq.ft × ₹18 = ₹225
      expect(lineAmountPaise(12500, 1800), 22500);
      // 0.333 × ₹1.00 = 33.3 paise → 33
      expect(lineAmountPaise(333, 100), 33);
      // 0.335 × ₹1.00 = 33.5 paise → 34
      expect(lineAmountPaise(335, 100), 34);
    });

    test('roundDiv rounds half away from zero', () {
      expect(roundDiv(5, 2), 3);
      expect(roundDiv(-5, 2), -3);
      expect(roundDiv(4, 3), 1);
      expect(roundDiv(5, 3), 2);
    });
  });

  group('measurement (BL-16)', () {
    test('wall area with door deduction', () {
      final entries = [
        // 2 walls of 12 ft × 10 ft
        const MeasurementEntry(nos: 2, lengthMilli: 12000, heightMilli: 10000),
        // door 3 ft × 7 ft
        const MeasurementEntry(
          lengthMilli: 3000,
          heightMilli: 7000,
          isDeduction: true,
        ),
      ];
      expect(measurementTotalMilli(entries), 219000); // 240 − 21 sq.ft
    });

    test('volume and running length', () {
      const volume = MeasurementEntry(
        lengthMilli: 10000,
        widthMilli: 750,
        heightMilli: 3000,
      );
      expect(volume.qtyMilli, 22500); // 10 × 0.75 × 3 = 22.5 cu.ft
      const length = MeasurementEntry(nos: 3, lengthMilli: 12500);
      expect(length.qtyMilli, 37500);
    });

    test('json round trip', () {
      const entry = MeasurementEntry(
        label: 'Hall',
        nos: 2,
        lengthMilli: 12000,
        heightMilli: 10000,
        isDeduction: true,
      );
      final copy = MeasurementEntry.fromJson(entry.toJson());
      expect(copy.label, 'Hall');
      expect(copy.qtyMilli, entry.qtyMilli);
      expect(copy.isDeduction, isTrue);
      expect(copy.widthMilli, isNull);
    });
  });

  group('phone (I-B7)', () {
    test('normalizes Indian mobiles', () {
      expect(normalizeIndianPhone('98765 43210'), '+919876543210');
      expect(normalizeIndianPhone('+91-98765-43210'), '+919876543210');
      expect(normalizeIndianPhone('09876543210'), '+919876543210');
      expect(normalizeIndianPhone('12345'), isNull);
      expect(normalizeIndianPhone('5876543210'), isNull);
      expect(normalizeIndianPhone(''), isNull);
    });

    test('formats for display', () {
      expect(formatIndianPhone('+919876543210'), '98765 43210');
    });
  });

  group('dates', () {
    test('financial year and document number (BL-10)', () {
      expect(financialYearLabel(DateTime(2026, 10, 3)), '26-27');
      expect(financialYearLabel(DateTime(2027, 2, 15)), '26-27');
      expect(financialYearLabel(DateTime(2026, 3, 31)), '25-26');
      expect(financialYearLabel(DateTime(2026, 4, 1)), '26-27');
      expect(
        documentNumber('INV', DateTime(2026, 10, 3), 1),
        'INV/26-27/0001',
      );
    });

    test('iso date round trip and days in month', () {
      expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
      expect(parseIsoDate('2026-01-05'), DateTime(2026, 1, 5));
      expect(daysInMonth(DateTime(2028, 2, 10)), 29);
      expect(daysInMonth(DateTime(2026, 12, 1)), 31);
    });
  });

  test('slug', () {
    expect(slug('CPVC pipe 1/2 inch'), 'cpvc_pipe_1_2_inch');
    expect(slug('Wire 1.5 sq.mm'), 'wire_1_5_sq_mm');
    expect(slug('  Cove / border '), 'cove_border');
  });
}
