import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/core/db/enums.dart';
import 'package:thekedaar/features/billing/domain/document_totals.dart';

void main() {
  test('discount in rupees (BL-05)', () {
    // ₹689.50 − ₹9 = ₹680.50 → rounds up to ₹681
    final totals = computeTotals([18950, 50000], discountPaise: 900);
    expect(totals.subtotalPaise, 68950);
    expect(totals.discountPaise, 900);
    expect(totals.roundOffPaise, 50);
    expect(totals.totalPaise, 68100);
  });

  test('discount in percent and round off to nearest rupee', () {
    // 10.5 × ₹18 + lump-sum ₹500 = ₹689; 10% off = ₹68.90; ₹620.10 → ₹620
    final totals = computeTotals(
      [18900, 50000],
      discountPercentBp: 1000,
    );
    expect(totals.subtotalPaise, 68900);
    expect(totals.discountPaise, 6890);
    expect(totals.roundOffPaise, -10);
    expect(totals.totalPaise, 62000);
  });

  test('half rupee rounds up; round off can be turned off', () {
    expect(computeTotals([10050]).totalPaise, 10100);
    expect(computeTotals([10049]).totalPaise, 10000);
    expect(computeTotals([10050], roundOff: false).totalPaise, 10050);
  });

  test('discount never exceeds the subtotal', () {
    final totals = computeTotals([5000], discountPaise: 9000, roundOff: false);
    expect(totals.discountPaise, 5000);
    expect(totals.totalPaise, 0);
  });

  test('line amount from qty and rate', () {
    const line = DraftLine(
      lineType: LineType.workRate,
      name: 'Plaster',
      qtyMilli: 219000,
      ratePaise: 1800,
    );
    expect(line.amountPaise, 394200); // 219 sq.ft × ₹18
  });

  test('next number per financial year (BL-10)', () {
    expect(nextSequence(const [], 'INV/26-27/'), 1);
    expect(
      nextSequence(
        const ['INV/26-27/0001', 'INV/26-27/0009', 'INV/25-26/0040'],
        'INV/26-27/',
      ),
      10,
    );
  });

  test('invoice status from payments (BL-13)', () {
    expect(statusAfterPayments(DocumentStatus.sent, 10000, 0),
        DocumentStatus.sent);
    expect(statusAfterPayments(DocumentStatus.sent, 10000, 4000),
        DocumentStatus.partiallyPaid);
    expect(statusAfterPayments(DocumentStatus.partiallyPaid, 10000, 10000),
        DocumentStatus.paid);
    expect(statusAfterPayments(DocumentStatus.paid, 12000, 10000),
        DocumentStatus.partiallyPaid);
    expect(statusAfterPayments(DocumentStatus.cancelled, 10000, 10000),
        DocumentStatus.cancelled);
  });
}
