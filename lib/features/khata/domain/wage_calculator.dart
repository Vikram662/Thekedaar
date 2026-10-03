import '../../../core/db/enums.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/decimal.dart';

/// A wage rate valid from [effectiveFrom] until the next rate (PRD I-S5).
class WageRate {
  const WageRate({
    required this.effectiveFrom,
    required this.model,
    required this.ratePaise,
    this.otRatePaise = 0,
    this.monthlyDivisor = 30,
  });

  final DateTime effectiveFrom;
  final WageModel model;

  /// Per day for daily, per month for monthly, unused for piece-rate.
  final int ratePaise;
  final int otRatePaise;

  /// 30, 26, or 0 = days in that month (PRD I-S1).
  final int monthlyDivisor;
}

class DayAttendance {
  const DayAttendance({
    required this.date,
    required this.status,
    this.otMilliHours = 0,
  });

  final DateTime date;
  final AttendanceStatus status;
  final int otMilliHours;
}

class WageInput {
  const WageInput({
    required this.rates,
    required this.days,
    this.piecePaise = 0,
    this.bonusPaise = 0,
    this.deductionPaise = 0,
    this.emiPaise = 0,
    this.advancePaise = 0,
    this.previousBalancePaise = 0,
  });

  final List<WageRate> rates;
  final List<DayAttendance> days;

  /// Sum of piece-work amounts in the period (PRD WK-05).
  final int piecePaise;
  final int bonusPaise;
  final int deductionPaise;
  final int emiPaise;
  final int advancePaise;

  /// Carry-forward from the last settlement: positive = admin owes the
  /// worker, negative = worker took more than earned (PRD I-S2).
  final int previousBalancePaise;
}

class WageResult {
  const WageResult({
    required this.paidHalfDays,
    required this.basePaise,
    required this.otPaise,
    required this.piecePaise,
    required this.bonusPaise,
    required this.deductionPaise,
    required this.emiPaise,
    required this.advancePaise,
    required this.previousBalancePaise,
  });

  /// Paid days × 2, so a half day stays an integer.
  final int paidHalfDays;
  final int basePaise;
  final int otPaise;
  final int piecePaise;
  final int bonusPaise;
  final int deductionPaise;
  final int emiPaise;
  final int advancePaise;
  final int previousBalancePaise;

  double get paidDays => paidHalfDays / 2;

  /// Base + OT + piece + bonus − deductions (PRD I-S3, before EMI/advance).
  int get earningPaise =>
      basePaise + otPaise + piecePaise + bonusPaise - deductionPaise;

  /// Earning − advance − EMI + previous balance (PRD KH-06).
  /// Negative means the worker owes money; it carries forward.
  int get netPayablePaise =>
      earningPaise - advancePaise - emiPaise + previousBalancePaise;
}

/// Computes a worker's earning for a period with integer paise only.
///
/// Rounding happens once per (rate, divisor) group, not per day, so a
/// monthly wage over a full month comes out exact.
WageResult calculateWages(WageInput input) {
  final rates = [...input.rates]
    ..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));

  // (rate index, divisor) → paid half-days
  final halvesByGroup = <(int, int), int>{};
  // rate index → OT milli-hours
  final otByRate = <int, int>{};
  var paidHalfDays = 0;

  for (final day in input.days) {
    final rateIndex = _rateIndexFor(rates, dateOnly(day.date));
    if (rateIndex == null) continue; // no wage set yet on that date
    final rate = rates[rateIndex];

    final halves = _paidHalves(day.status, rate.model);
    paidHalfDays += halves;
    if (halves > 0 && rate.model != WageModel.piece) {
      final divisor = switch (rate.model) {
        WageModel.monthly => rate.monthlyDivisor == 0
            ? daysInMonth(day.date)
            : rate.monthlyDivisor,
        _ => 1,
      };
      halvesByGroup.update(
        (rateIndex, divisor),
        (value) => value + halves,
        ifAbsent: () => halves,
      );
    }
    if (day.otMilliHours > 0) {
      otByRate.update(
        rateIndex,
        (value) => value + day.otMilliHours,
        ifAbsent: () => day.otMilliHours,
      );
    }
  }

  var basePaise = 0;
  halvesByGroup.forEach((group, halves) {
    final (rateIndex, divisor) = group;
    basePaise += roundDiv(rates[rateIndex].ratePaise * halves, 2 * divisor);
  });

  var otPaise = 0;
  otByRate.forEach((rateIndex, milliHours) {
    otPaise += roundDiv(rates[rateIndex].otRatePaise * milliHours, 1000);
  });

  return WageResult(
    paidHalfDays: paidHalfDays,
    basePaise: basePaise,
    otPaise: otPaise,
    piecePaise: input.piecePaise,
    bonusPaise: input.bonusPaise,
    deductionPaise: input.deductionPaise,
    emiPaise: input.emiPaise,
    advancePaise: input.advancePaise,
    previousBalancePaise: input.previousBalancePaise,
  );
}

int? _rateIndexFor(List<WageRate> sortedRates, DateTime date) {
  int? found;
  for (var i = 0; i < sortedRates.length; i++) {
    if (dateOnly(sortedRates[i].effectiveFrom).isAfter(date)) break;
    found = i;
  }
  return found;
}

/// Paid half-days for one day. Weekly off is paid only on a monthly wage.
int _paidHalves(AttendanceStatus status, WageModel model) => switch (status) {
      AttendanceStatus.present || AttendanceStatus.leavePaid => 2,
      AttendanceStatus.half => 1,
      AttendanceStatus.off => model == WageModel.monthly ? 2 : 0,
      AttendanceStatus.absent || AttendanceStatus.leaveUnpaid => 0,
    };
