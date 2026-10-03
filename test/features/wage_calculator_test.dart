import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/core/db/enums.dart';
import 'package:thekedaar/features/khata/domain/wage_calculator.dart';

List<DayAttendance> _days(
  DateTime start,
  int count,
  AttendanceStatus status, {
  int otMilliHours = 0,
}) =>
    [
      for (var i = 0; i < count; i++)
        DayAttendance(
          date: DateTime(start.year, start.month, start.day + i),
          status: status,
          otMilliHours: otMilliHours,
        ),
    ];

void main() {
  final oct1 = DateTime(2026, 10, 1);

  test('daily wage with half days and absents', () {
    final result = calculateWages(WageInput(
      rates: [
        WageRate(effectiveFrom: oct1, model: WageModel.daily, ratePaise: 60000),
      ],
      days: [
        ..._days(oct1, 20, AttendanceStatus.present),
        ..._days(DateTime(2026, 10, 21), 2, AttendanceStatus.half),
        ..._days(DateTime(2026, 10, 23), 1, AttendanceStatus.absent),
        ..._days(DateTime(2026, 10, 24), 1, AttendanceStatus.off),
      ],
    ));
    expect(result.paidDays, 21);
    expect(result.basePaise, 1260000); // ₹12,600
  });

  test('monthly wage, divisor 30, weekly offs paid', () {
    final result = calculateWages(WageInput(
      rates: [
        WageRate(
          effectiveFrom: oct1,
          model: WageModel.monthly,
          ratePaise: 1800000,
        ),
      ],
      days: [
        ..._days(oct1, 26, AttendanceStatus.present),
        ..._days(DateTime(2026, 10, 27), 4, AttendanceStatus.off),
        ..._days(DateTime(2026, 10, 31), 1, AttendanceStatus.absent),
      ],
    ));
    expect(result.paidDays, 30);
    expect(result.basePaise, 1800000);
  });

  test('monthly wage, divisor = days in month, full month is exact', () {
    final result = calculateWages(WageInput(
      rates: [
        WageRate(
          effectiveFrom: oct1,
          model: WageModel.monthly,
          ratePaise: 1800000,
          monthlyDivisor: 0,
        ),
      ],
      days: _days(oct1, 31, AttendanceStatus.present),
    ));
    expect(result.basePaise, 1800000);
  });

  test('rate change in the middle of the month (I-S5)', () {
    final result = calculateWages(WageInput(
      rates: [
        WageRate(
          effectiveFrom: DateTime(2026, 10, 11),
          model: WageModel.daily,
          ratePaise: 70000,
        ),
        WageRate(effectiveFrom: oct1, model: WageModel.daily, ratePaise: 60000),
      ],
      days: _days(oct1, 20, AttendanceStatus.present),
    ));
    expect(result.basePaise, 600000 + 700000);
  });

  test('days before the first wage rate earn nothing', () {
    final result = calculateWages(WageInput(
      rates: [
        WageRate(
          effectiveFrom: DateTime(2026, 10, 6),
          model: WageModel.daily,
          ratePaise: 50000,
        ),
      ],
      days: _days(oct1, 10, AttendanceStatus.present),
    ));
    expect(result.basePaise, 5 * 50000);
  });

  test('OT hours use the OT rate', () {
    final result = calculateWages(WageInput(
      rates: [
        WageRate(
          effectiveFrom: oct1,
          model: WageModel.daily,
          ratePaise: 60000,
          otRatePaise: 10000,
        ),
      ],
      days: _days(oct1, 2, AttendanceStatus.present, otMilliHours: 2500),
    ));
    expect(result.otPaise, 50000); // 5 h × ₹100
  });

  test('piece-rate worker earns only from piece work', () {
    final result = calculateWages(WageInput(
      rates: [
        WageRate(effectiveFrom: oct1, model: WageModel.piece, ratePaise: 0),
      ],
      days: _days(oct1, 10, AttendanceStatus.present),
      piecePaise: 1500000,
    ));
    expect(result.basePaise, 0);
    expect(result.earningPaise, 1500000);
  });

  test('net payable: earning − advance − EMI + carry-forward (KH-06)', () {
    final result = calculateWages(WageInput(
      rates: [
        WageRate(effectiveFrom: oct1, model: WageModel.daily, ratePaise: 60000),
      ],
      days: _days(oct1, 21, AttendanceStatus.present),
      piecePaise: 50000,
      bonusPaise: 20000,
      deductionPaise: 10000,
      advancePaise: 400000,
      emiPaise: 100000,
      previousBalancePaise: -20000,
    ));
    expect(result.earningPaise, 1260000 + 50000 + 20000 - 10000);
    expect(result.netPayablePaise, 1320000 - 400000 - 100000 - 20000);
  });

  test('advance larger than earning gives negative balance', () {
    final result = calculateWages(WageInput(
      rates: [
        WageRate(effectiveFrom: oct1, model: WageModel.daily, ratePaise: 60000),
      ],
      days: _days(oct1, 5, AttendanceStatus.present),
      advancePaise: 500000,
    ));
    expect(result.netPayablePaise, -200000);
  });
}
