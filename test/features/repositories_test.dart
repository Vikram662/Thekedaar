import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/core/db/audit.dart';
import 'package:thekedaar/core/db/database.dart';
import 'package:thekedaar/core/db/enums.dart';
import 'package:thekedaar/core/seed/seed_service.dart';
import 'package:thekedaar/core/utils/dates.dart';
import 'package:thekedaar/features/attendance/data/attendance_repository.dart';
import 'package:thekedaar/features/billing/data/billing_repository.dart';
import 'package:thekedaar/features/billing/domain/document_totals.dart';
import 'package:thekedaar/features/khata/data/khata_repository.dart';
import 'package:thekedaar/features/workers/data/workers_repository.dart';

/// Dates relative to today so the tests never depend on the calendar.
DateTime day(int offset) {
  final t = DateTime.now();
  return DateTime(t.year, t.month, t.day + offset);
}

void main() {
  late AppDatabase db;
  late WorkersRepository workers;
  late AttendanceRepository attendance;
  late KhataRepository khata;
  late BillingRepository billing;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    workers = WorkersRepository(db);
    attendance = AttendanceRepository(db);
    khata = KhataRepository(db);
    billing = BillingRepository(db);
  });

  tearDown(() => db.close());

  Future<String> addDailyWorker({int ratePaise = 60000, int joinedDaysAgo = 20}) =>
      workers.addWorker(NewWorker(
        name: 'Raju',
        joinDate: day(-joinedDaysAgo),
        wageModel: WageModel.daily,
        ratePaise: ratePaise,
      ));

  group('attendance', () {
    test('marking twice updates, not duplicates', () async {
      final id = await addDailyWorker();
      await attendance.setStatus(
          workerId: id, date: day(-1), status: AttendanceStatus.present);
      await attendance.setStatus(
          workerId: id, date: day(-1), status: AttendanceStatus.half);
      final rows = await db.select(db.attendances).get();
      expect(rows, hasLength(1));
      expect(rows.single.status, AttendanceStatus.half);
      // Past-day change is audited (I-T3).
      final audits = await db.select(db.auditLogs).get();
      expect(audits.where((a) => a.entity == 'attendance'), hasLength(1));
    });

    test('mark all present and copy yesterday (AT-02)', () async {
      final a = await addDailyWorker();
      final b = await addDailyWorker();
      await attendance.setStatus(
          workerId: a, date: day(-1), status: AttendanceStatus.absent);
      expect(await attendance.markAllUnmarked(day(-1), AttendanceStatus.present), 1);
      expect(await attendance.copyDay(from: day(-1), to: day(0)), 2);
      final today = await attendance.watchDay(day(0)).first;
      final byId = {for (final r in today) r.worker.id: r.attendance?.status};
      expect(byId[a], AttendanceStatus.absent);
      expect(byId[b], AttendanceStatus.present);
    });

    test('workers who joined later are not listed', () async {
      await addDailyWorker(joinedDaysAgo: 2);
      expect(await attendance.watchDay(day(-5)).first, isEmpty);
      expect(await attendance.watchDay(day(-1)).first, hasLength(1));
    });
  });

  group('khata', () {
    test('summary: wages + piece work − advance (KH-03)', () async {
      final id = await addDailyWorker();
      for (var d = -10; d <= -6; d++) {
        await attendance.setStatus(
            workerId: id, date: day(d), status: AttendanceStatus.present);
      }
      await attendance.setStatus(
          workerId: id, date: day(-5), status: AttendanceStatus.half);
      await khata.addEntry(
        workerId: id,
        type: LedgerType.advance,
        amountPaise: 100000,
        at: day(-7).add(const Duration(hours: 10)),
        mode: PaymentMode.cash,
      );
      await khata.addPieceWork(
        workerId: id,
        date: day(-6),
        description: 'Floor tiling',
        qtyMilli: 10000,
        ratePaise: 2500,
      );

      final s = await khata.computeSummary(id);
      expect(s.counts.present, 5);
      expect(s.counts.half, 1);
      expect(s.result.basePaise, 5 * 60000 + 30000);
      expect(s.result.piecePaise, 25000);
      expect(s.result.advancePaise, 100000);
      expect(s.balancePaise, 330000 + 25000 - 100000);
    });

    test('reversed advance no longer counts (KH-02)', () async {
      final id = await addDailyWorker();
      final entryId = await khata.addEntry(
        workerId: id,
        type: LedgerType.advance,
        amountPaise: 5000,
        at: day(-1),
      );
      await khata.reverseEntry(entryId);
      expect((await khata.computeSummary(id)).result.advancePaise, 0);
      expect(() => khata.reverseEntry(entryId), throwsStateError);
    });

    test('settlement locks the period and carries forward (KH-06)', () async {
      final id = await addDailyWorker();
      for (var d = -10; d <= -6; d++) {
        await attendance.setStatus(
            workerId: id, date: day(d), status: AttendanceStatus.present);
      }
      await khata.addEntry(
          workerId: id,
          type: LedgerType.advance,
          amountPaise: 50000,
          at: day(-8));
      await khata.addPieceWork(
        workerId: id,
        date: day(-7),
        description: 'Plaster',
        qtyMilli: 1000,
        ratePaise: 10000,
      );

      // Earned 5 × 600 + 100 = 3,100; advance 500 → net 2,600; pay 2,000.
      final settlement = await khata.settle(
        workerId: id,
        periodTo: day(-5),
        paidPaise: 200000,
      );
      expect(settlement.earningPaise, 310000);
      expect(settlement.carryForwardPaise, 60000);

      // Locked days refuse changes (AT-06).
      expect(
        () => attendance.setStatus(
            workerId: id, date: day(-8), status: AttendanceStatus.absent),
        throwsA(isA<PeriodLockedException>()),
      );
      expect(
        () => khata.addEntry(
            workerId: id,
            type: LedgerType.advance,
            amountPaise: 100,
            at: day(-8)),
        throwsA(isA<PeriodLockedException>()),
      );

      // Next period starts after the settled date, with the carry forward.
      await attendance.setStatus(
          workerId: id, date: day(-2), status: AttendanceStatus.present);
      final next = await khata.computeSummary(id);
      expect(next.periodFrom, day(-4));
      expect(next.result.previousBalancePaise, 60000);
      expect(next.result.advancePaise, 0); // settlement payout not counted
      expect(next.balancePaise, 60000 + 60000);

      final pieces = await db.select(db.pieceWorks).get();
      expect(pieces.single.settlementId, settlement.id);
    });

    test('reversing a settlement reopens it and keeps the payment', () async {
      final id = await addDailyWorker();
      for (var d = -10; d <= -6; d++) {
        await attendance.setStatus(
            workerId: id, date: day(d), status: AttendanceStatus.present);
      }
      final settlement = await khata.settle(
        workerId: id,
        periodTo: day(-5),
        paidPaise: 100000,
      );
      await khata.reverseSettlement(settlement.id);

      final s = await khata.computeSummary(id);
      expect(s.periodFrom, day(-20));
      expect(s.result.basePaise, 300000);
      expect(s.result.advancePaise, 100000); // money already paid stays
      expect(s.balancePaise, 200000);
      final pieces = await db.select(db.settlements).get();
      expect(pieces.single.status, SettlementStatus.reversed);
    });

    test('only the latest settlement can be reversed', () async {
      final id = await addDailyWorker();
      final first =
          await khata.settle(workerId: id, periodTo: day(-10), paidPaise: 0);
      await khata.settle(workerId: id, periodTo: day(-5), paidPaise: 0);
      expect(() => khata.reverseSettlement(first.id), throwsStateError);
    });
  });

  group('billing', () {
    Future<String> client() => billing.saveClient(name: 'Sharma ji');

    DocumentDraft draft(String clientId, DocumentKind kind, {String? itemId}) =>
        DocumentDraft(
          kind: kind,
          clientId: clientId,
          date: DateTime(2026, 10, 3),
          lines: [
            DraftLine(
              lineType: LineType.workRate,
              name: 'Light point',
              qtyMilli: 10500,
              ratePaise: 1800,
              itemId: itemId,
            ),
            const DraftLine(
              lineType: LineType.lumpSum,
              name: 'Fitting',
              qtyMilli: 1000,
              ratePaise: 50000,
            ),
          ],
          discountPercentBp: 1000,
        );

    test('numbering per kind and financial year (BL-10)', () async {
      final c = await client();
      final i1 = await billing.saveDocument(draft(c, DocumentKind.invoice));
      final i2 = await billing.saveDocument(draft(c, DocumentKind.invoice));
      final q1 = await billing.saveDocument(draft(c, DocumentKind.quotation));
      Future<String> number(String id) async =>
          (await billing.watchDocument(id).first)!.document.number;
      expect(await number(i1), 'INV/26-27/0001');
      expect(await number(i2), 'INV/26-27/0002');
      expect(await number(q1), 'QT/26-27/0001');
    });

    test('totals, payments and client balance (BL-05, BL-13)', () async {
      final c = await client();
      final id = await billing.saveDocument(draft(c, DocumentKind.invoice));
      final saved = (await billing.watchDocument(id).first)!;
      expect(saved.document.totalPaise, 62000);
      expect(saved.lines, hasLength(2));

      await billing.markSentIfDraft(id);
      await billing.recordPayment(
        clientId: c,
        documentId: id,
        amountPaise: 30000,
        mode: PaymentMode.gPay,
        date: DateTime(2026, 10, 4),
      );
      expect((await billing.watchDocument(id).first)!.document.status,
          DocumentStatus.partiallyPaid);

      var balance = (await billing.watchClients().first).single;
      expect(balance.outstandingPaise, 32000);

      await billing.recordPayment(
        clientId: c,
        documentId: id,
        amountPaise: 32000,
        mode: PaymentMode.cash,
        date: DateTime(2026, 10, 5),
      );
      expect((await billing.watchDocument(id).first)!.document.status,
          DocumentStatus.paid);
      balance = (await billing.watchClients().first).single;
      expect(balance.outstandingPaise, 0);
    });

    test('quotation converts to a new invoice (BL-08)', () async {
      final c = await client();
      final q = await billing.saveDocument(draft(c, DocumentKind.quotation));
      final inv = await billing.convertToInvoice(q);
      final invoice = (await billing.watchDocument(inv).first)!;
      expect(invoice.document.kind, DocumentKind.invoice);
      expect(invoice.document.sourceQuotationId, q);
      expect(invoice.document.totalPaise, 62000);
      expect((await billing.watchDocument(q).first)!.convertedInvoiceId, inv);
    });

    test('editing a sent bill bumps its revision (I-B6)', () async {
      final c = await client();
      final id = await billing.saveDocument(draft(c, DocumentKind.invoice));
      await billing.markSentIfDraft(id);
      final current = draft(c, DocumentKind.invoice);
      await billing.saveDocument(DocumentDraft(
        id: id,
        kind: current.kind,
        clientId: c,
        date: current.date,
        lines: current.lines.take(1).toList(),
      ));
      final edited = (await billing.watchDocument(id).first)!;
      expect(edited.document.revision, 2);
      expect(edited.lines, hasLength(1));
    });

    test('item rates used on a bill are remembered (D-8)', () async {
      await SeedService(
        db,
        (name) => File('assets/seed/$name.json').readAsString(),
      ).applyTrades({Trade.electrical});
      final item = await (db.select(db.itemMasters)
            ..where((i) => i.seedKey.equals(itemSeedKey('Light point'))))
          .getSingle();
      expect(item.defaultRatePaise, isNull);

      final c = await client();
      await billing.saveDocument(
          draft(c, DocumentKind.quotation, itemId: item.id));
      final updated = await (db.select(db.itemMasters)
            ..where((i) => i.id.equals(item.id)))
          .getSingle();
      expect(updated.defaultRatePaise, 1800);
    });
  });

  test('dates helper sanity', () {
    expect(isoDate(day(0)), isoDate(DateTime.now()));
  });
}
