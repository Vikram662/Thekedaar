import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/audit.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/db/watch.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/qty.dart';
import '../domain/wage_calculator.dart';

final khataRepositoryProvider = Provider<KhataRepository>(
  (ref) => KhataRepository(ref.watch(databaseProvider)),
);

/// Live balance for the open (unsettled) period (PRD KH-03).
final workerSummaryProvider = StreamProvider.family<WorkerSummary, String>(
  (ref, workerId) =>
      ref.watch(khataRepositoryProvider).watchSummary(workerId),
);

/// Every worker's open balance, for the Lena / Dena report.
final allWorkerBalancesProvider = StreamProvider<List<WorkerBalance>>(
  (ref) => ref.watch(khataRepositoryProvider).watchAllBalances(),
);

final workerLedgerProvider = StreamProvider.family<List<LedgerItem>, String>(
  (ref, workerId) => ref.watch(khataRepositoryProvider).watchLedger(workerId),
);

final recentLedgerProvider = StreamProvider<List<LedgerItem>>(
  (ref) => ref.watch(khataRepositoryProvider).watchLedger(null, limit: 100),
);

final workerPieceWorkProvider =
    StreamProvider.family<List<PieceWorkItem>, String>(
  (ref, workerId) =>
      ref.watch(khataRepositoryProvider).watchPieceWork(workerId),
);

final workerSettlementsProvider =
    StreamProvider.family<List<Settlement>, String>(
  (ref, workerId) =>
      ref.watch(khataRepositoryProvider).watchSettlements(workerId),
);

class LedgerItem {
  const LedgerItem({
    required this.entry,
    required this.workerName,
    required this.reversed,
  });

  final LedgerEntry entry;
  final String workerName;

  /// A reversal entry exists for this entry (PRD KH-02).
  final bool reversed;

  DateTime get at => DateTime.fromMillisecondsSinceEpoch(entry.at);
}

class PieceWorkItem {
  const PieceWorkItem({required this.work, this.unitCode});

  final PieceWork work;
  final String? unitCode;
}

class AttendanceCounts {
  const AttendanceCounts({
    this.present = 0,
    this.half = 0,
    this.absent = 0,
    this.leave = 0,
    this.off = 0,
  });

  final int present;
  final int half;
  final int absent;
  final int leave;
  final int off;
}

class WorkerSummary {
  const WorkerSummary({
    required this.periodFrom,
    required this.periodTo,
    required this.result,
    required this.counts,
    this.lastSettlement,
  });

  final DateTime periodFrom;
  final DateTime periodTo;
  final WageResult result;
  final AttendanceCounts counts;
  final Settlement? lastSettlement;

  int get balancePaise => result.netPayablePaise;
}

class WorkerBalance {
  const WorkerBalance({required this.worker, required this.summary});

  final Worker worker;
  final WorkerSummary summary;

  /// Positive: admin has to pay (dena). Negative: worker owes (lena).
  int get balancePaise => summary.balancePaise;
}

class KhataRepository {
  KhataRepository(this._db);

  final AppDatabase _db;

  // ─── Periods ──────────────────────────────────────────────────────────────

  Future<Settlement?> lastLockedSettlement(String workerId) =>
      (_db.select(_db.settlements)
            ..where((s) =>
                s.workerId.equals(workerId) &
                s.status.equalsValue(SettlementStatus.locked))
            ..orderBy([(s) => OrderingTerm.desc(s.periodTo)])
            ..limit(1))
          .getSingleOrNull();

  /// First day of the open period: day after the last settlement, or joining.
  Future<DateTime> openPeriodStart(String workerId) async {
    final last = await lastLockedSettlement(workerId);
    if (last != null) {
      final to = parseIsoDate(last.periodTo);
      return DateTime(to.year, to.month, to.day + 1);
    }
    final worker = await (_db.select(_db.workers)
          ..where((w) => w.id.equals(workerId)))
        .getSingle();
    return parseIsoDate(worker.joinDate);
  }

  Future<void> _ensureOpen(String workerId, DateTime date) async {
    final start = await openPeriodStart(workerId);
    if (dateOnly(date).isBefore(start)) {
      throw const PeriodLockedException(
        'This date is in a settled period. Pick a later date.',
      );
    }
  }

  // ─── Ledger (advance, bonus, deduction) ───────────────────────────────────

  Future<String> addEntry({
    required String workerId,
    required LedgerType type,
    required int amountPaise,
    required DateTime at,
    PaymentMode? mode,
    String? remarks,
  }) async {
    if (amountPaise <= 0) throw ArgumentError('Amount must be more than 0');
    final id = newId();
    await _db.transaction(() async {
      await _ensureOpen(workerId, at);
      await _db.into(_db.ledgerEntries).insert(LedgerEntriesCompanion.insert(
            id: id,
            workerId: workerId,
            entryType: type,
            amountPaise: amountPaise,
            mode: Value(mode),
            at: at.millisecondsSinceEpoch,
            remarks: Value(remarks),
          ));
      await writeAudit(_db,
          entity: 'ledger',
          entityId: id,
          action: AuditAction.create,
          after: {
            'workerId': workerId,
            'type': type.name,
            'amountPaise': amountPaise,
          });
    });
    return id;
  }

  /// Entries are never edited or deleted; a reversal cancels one (PRD I-S4).
  Future<void> reverseEntry(String entryId, {String? reason}) async {
    await _db.transaction(() async {
      final entry = await (_db.select(_db.ledgerEntries)
            ..where((e) => e.id.equals(entryId)))
          .getSingle();
      if (entry.entryType == LedgerType.reversal) {
        throw StateError('A reversal cannot be reversed');
      }
      final already = await (_db.select(_db.ledgerEntries)
            ..where((e) =>
                e.refId.equals(entryId) &
                e.entryType.equalsValue(LedgerType.reversal)))
          .getSingleOrNull();
      if (already != null) throw StateError('Already reversed');
      await _ensureOpen(
          entry.workerId, DateTime.fromMillisecondsSinceEpoch(entry.at));

      final id = newId();
      await _db.into(_db.ledgerEntries).insert(LedgerEntriesCompanion.insert(
            id: id,
            workerId: entry.workerId,
            entryType: LedgerType.reversal,
            amountPaise: entry.amountPaise,
            mode: Value(entry.mode),
            at: DateTime.now().millisecondsSinceEpoch,
            remarks: Value(reason ?? 'Reversed'),
            refId: Value(entryId),
          ));
      await writeAudit(_db,
          entity: 'ledger',
          entityId: entryId,
          action: AuditAction.reverse,
          before: entry.toJson());
    });
  }

  Stream<List<LedgerItem>> watchLedger(String? workerId, {int? limit}) {
    final query = _db.select(_db.ledgerEntries).join([
      innerJoin(
          _db.workers, _db.workers.id.equalsExp(_db.ledgerEntries.workerId)),
    ]);
    if (workerId != null) {
      query.where(_db.ledgerEntries.workerId.equals(workerId));
    }
    query.orderBy([OrderingTerm.desc(_db.ledgerEntries.at)]);
    if (limit != null) query.limit(limit);
    return query.watch().asyncMap((rows) async {
      final reversals = await (_db.select(_db.ledgerEntries)
            ..where((e) => e.entryType.equalsValue(LedgerType.reversal)))
          .get();
      final reversedIds = {for (final r in reversals) r.refId};
      return [
        for (final row in rows)
          LedgerItem(
            entry: row.readTable(_db.ledgerEntries),
            workerName: row.readTable(_db.workers).name,
            reversed: reversedIds.contains(row.readTable(_db.ledgerEntries).id),
          ),
      ];
    });
  }

  // ─── Piece work (PRD WK-05) ───────────────────────────────────────────────

  Future<String> addPieceWork({
    required String workerId,
    required DateTime date,
    required String description,
    required int qtyMilli,
    required int ratePaise,
    String? itemId,
    String? unitId,
    String? jobId,
  }) async {
    final id = newId();
    await _db.transaction(() async {
      await _ensureOpen(workerId, date);
      await _db.into(_db.pieceWorks).insert(PieceWorksCompanion.insert(
            id: id,
            workerId: workerId,
            date: isoDate(date),
            description: description,
            qtyMilli: qtyMilli,
            ratePaise: ratePaise,
            amountPaise: lineAmountPaise(qtyMilli, ratePaise),
            itemId: Value(itemId),
            unitId: Value(unitId),
            jobId: Value(jobId),
          ));
      await writeAudit(_db,
          entity: 'piece_work', entityId: id, action: AuditAction.create);
    });
    return id;
  }

  /// Only unsettled piece work can be removed; it is audited.
  Future<void> deletePieceWork(String id) async {
    await _db.transaction(() async {
      final work = await (_db.select(_db.pieceWorks)
            ..where((p) => p.id.equals(id)))
          .getSingle();
      if (work.settlementId != null) throw const PeriodLockedException();
      await (_db.delete(_db.pieceWorks)..where((p) => p.id.equals(id))).go();
      await writeAudit(_db,
          entity: 'piece_work',
          entityId: id,
          action: AuditAction.delete,
          before: work.toJson());
    });
  }

  Stream<List<PieceWorkItem>> watchPieceWork(String workerId) {
    final query = _db.select(_db.pieceWorks).join([
      leftOuterJoin(_db.units, _db.units.id.equalsExp(_db.pieceWorks.unitId)),
    ])
      ..where(_db.pieceWorks.workerId.equals(workerId))
      ..orderBy([OrderingTerm.desc(_db.pieceWorks.date)])
      ..limit(50);
    return query.watch().map((rows) => [
          for (final row in rows)
            PieceWorkItem(
              work: row.readTable(_db.pieceWorks),
              unitCode: row.readTableOrNull(_db.units)?.code,
            ),
        ]);
  }

  // ─── Summary & settlement (PRD KH-03, KH-06) ──────────────────────────────

  Stream<WorkerSummary> watchSummary(String workerId) => watchComputed(
        _db,
        [
          _db.attendances,
          _db.ledgerEntries,
          _db.pieceWorks,
          _db.settlements,
          _db.wageHistories,
        ],
        () => computeSummary(workerId),
      );

  Stream<List<WorkerBalance>> watchAllBalances() => watchComputed(
        _db,
        [
          _db.workers,
          _db.attendances,
          _db.ledgerEntries,
          _db.pieceWorks,
          _db.settlements,
          _db.wageHistories,
        ],
        () async {
          final workers = await (_db.select(_db.workers)
                ..orderBy([(w) => OrderingTerm.asc(w.name)]))
              .get();
          return [
            for (final w in workers)
              WorkerBalance(worker: w, summary: await computeSummary(w.id)),
          ];
        },
      );

  Future<WorkerSummary> computeSummary(
    String workerId, {
    DateTime? periodTo,
  }) async {
    final last = await lastLockedSettlement(workerId);
    final from = await openPeriodStart(workerId);
    final to = dateOnly(periodTo ?? DateTime.now());
    final fromIso = isoDate(from);
    final toIso = isoDate(to);

    final wages = await (_db.select(_db.wageHistories)
          ..where((w) => w.workerId.equals(workerId)))
        .get();
    final attendance = await (_db.select(_db.attendances)
          ..where((a) =>
              a.workerId.equals(workerId) &
              a.date.isBetweenValues(fromIso, toIso)))
        .get();
    final pieces = await (_db.select(_db.pieceWorks)
          ..where((p) =>
              p.workerId.equals(workerId) &
              p.settlementId.isNull() &
              p.date.isSmallerOrEqualValue(toIso)))
        .get();
    final entries = await (_db.select(_db.ledgerEntries)
          ..where((e) => e.workerId.equals(workerId)))
        .get();

    final reversedIds = {
      for (final e in entries)
        if (e.entryType == LedgerType.reversal) e.refId,
    };
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = DateTime(to.year, to.month, to.day + 1).millisecondsSinceEpoch;
    var advance = 0, bonus = 0, deduction = 0;
    for (final e in entries) {
      if (reversedIds.contains(e.id)) continue;
      if (e.at < fromMs || e.at >= toMs) continue;
      switch (e.entryType) {
        case LedgerType.advance:
          advance += e.amountPaise;
        case LedgerType.payment:
          // Settlement payouts carry the settlement id and belong to that
          // settlement, not to the open period.
          if (e.refId == null) advance += e.amountPaise;
        case LedgerType.bonus:
          bonus += e.amountPaise;
        case LedgerType.deduction:
          deduction += e.amountPaise;
        case LedgerType.emi ||
              LedgerType.reversal ||
              LedgerType.carryForward:
          break;
      }
    }

    var present = 0, half = 0, absent = 0, leave = 0, off = 0;
    for (final a in attendance) {
      switch (a.status) {
        case AttendanceStatus.present:
          present++;
        case AttendanceStatus.half:
          half++;
        case AttendanceStatus.absent:
          absent++;
        case AttendanceStatus.leavePaid || AttendanceStatus.leaveUnpaid:
          leave++;
        case AttendanceStatus.off:
          off++;
      }
    }

    final result = calculateWages(WageInput(
      rates: [
        for (final w in wages)
          WageRate(
            effectiveFrom: parseIsoDate(w.effectiveFrom),
            model: w.model,
            ratePaise: w.ratePaise,
            otRatePaise: w.otRatePaise,
            monthlyDivisor: w.monthlyDivisor,
          ),
      ],
      days: [
        for (final a in attendance)
          DayAttendance(
            date: parseIsoDate(a.date),
            status: a.status,
            otMilliHours: a.otMilliHours,
          ),
      ],
      piecePaise: pieces.fold(0, (sum, p) => sum + p.amountPaise),
      bonusPaise: bonus,
      deductionPaise: deduction,
      advancePaise: advance,
      previousBalancePaise: last?.carryForwardPaise ?? 0,
    ));

    return WorkerSummary(
      periodFrom: from,
      periodTo: to,
      result: result,
      counts: AttendanceCounts(
        present: present,
        half: half,
        absent: absent,
        leave: leave,
        off: off,
      ),
      lastSettlement: last,
    );
  }

  /// Locks the period, records the payout and carries the rest forward
  /// (PRD I-S2, KH-06). Nothing is zeroed out.
  Future<Settlement> settle({
    required String workerId,
    required DateTime periodTo,
    required int paidPaise,
    PaymentMode mode = PaymentMode.cash,
  }) async {
    if (paidPaise < 0) throw ArgumentError('Paid amount cannot be negative');
    late Settlement settlement;
    await _db.transaction(() async {
      final summary = await computeSummary(workerId, periodTo: periodTo);
      if (summary.periodTo.isBefore(summary.periodFrom)) {
        throw StateError('Nothing to settle before this date');
      }
      final id = newId();
      final net = summary.result.netPayablePaise;
      await _db.into(_db.settlements).insert(SettlementsCompanion.insert(
            id: id,
            workerId: workerId,
            periodFrom: isoDate(summary.periodFrom),
            periodTo: isoDate(summary.periodTo),
            earningPaise: summary.result.earningPaise,
            advancePaise: summary.result.advancePaise,
            emiPaise: Value(summary.result.emiPaise),
            paidPaise: paidPaise,
            carryForwardPaise: net - paidPaise,
            status: SettlementStatus.locked,
          ));
      if (paidPaise > 0) {
        await _db.into(_db.ledgerEntries).insert(LedgerEntriesCompanion.insert(
              id: newId(),
              workerId: workerId,
              entryType: LedgerType.payment,
              amountPaise: paidPaise,
              mode: Value(mode),
              at: DateTime.now().millisecondsSinceEpoch,
              remarks: const Value('Settlement'),
              refId: Value(id),
            ));
      }
      await (_db.update(_db.pieceWorks)
            ..where((p) =>
                p.workerId.equals(workerId) &
                p.settlementId.isNull() &
                p.date.isSmallerOrEqualValue(isoDate(summary.periodTo))))
          .write(PieceWorksCompanion(settlementId: Value(id)));
      settlement = await (_db.select(_db.settlements)
            ..where((s) => s.id.equals(id)))
          .getSingle();
      await writeAudit(_db,
          entity: 'settlement',
          entityId: id,
          action: AuditAction.create,
          after: settlement.toJson());
    });
    return settlement;
  }

  /// PRD KH-10: undo the latest settlement (caller re-verifies the admin).
  Future<void> reverseSettlement(String settlementId) async {
    await _db.transaction(() async {
      final settlement = await (_db.select(_db.settlements)
            ..where((s) => s.id.equals(settlementId)))
          .getSingle();
      final latest = await lastLockedSettlement(settlement.workerId);
      if (latest?.id != settlementId) {
        throw StateError('Only the latest settlement can be reversed');
      }
      await (_db.update(_db.settlements)
            ..where((s) => s.id.equals(settlementId)))
          .write(SettlementsCompanion(
        status: const Value(SettlementStatus.reversed),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));
      final payments = await (_db.select(_db.ledgerEntries)
            ..where((e) =>
                e.refId.equals(settlementId) &
                e.entryType.equalsValue(LedgerType.payment)))
          .get();
      // The cash really went out, so it stays on record: the settlement
      // payout is reversed and re-entered as a plain payment, which counts
      // against the reopened period.
      for (final payment in payments) {
        await _db.into(_db.ledgerEntries).insert(LedgerEntriesCompanion.insert(
              id: newId(),
              workerId: payment.workerId,
              entryType: LedgerType.reversal,
              amountPaise: payment.amountPaise,
              mode: Value(payment.mode),
              at: DateTime.now().millisecondsSinceEpoch,
              remarks: const Value('Settlement reversed'),
              refId: Value(payment.id),
            ));
        await _db.into(_db.ledgerEntries).insert(LedgerEntriesCompanion.insert(
              id: newId(),
              workerId: payment.workerId,
              entryType: LedgerType.payment,
              amountPaise: payment.amountPaise,
              mode: Value(payment.mode),
              at: payment.at,
              remarks: const Value('Paid at reversed settlement'),
            ));
      }
      await (_db.update(_db.pieceWorks)
            ..where((p) => p.settlementId.equals(settlementId)))
          .write(const PieceWorksCompanion(settlementId: Value(null)));
      await writeAudit(_db,
          entity: 'settlement',
          entityId: settlementId,
          action: AuditAction.reverse,
          before: settlement.toJson());
    });
  }

  Stream<List<Settlement>> watchSettlements(String workerId) =>
      (_db.select(_db.settlements)
            ..where((s) => s.workerId.equals(workerId))
            ..orderBy([(s) => OrderingTerm.desc(s.periodTo)]))
          .watch();

  Future<Settlement> settlementById(String id) =>
      (_db.select(_db.settlements)..where((s) => s.id.equals(id))).getSingle();
}
