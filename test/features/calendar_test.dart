import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/core/db/database.dart';
import 'package:thekedaar/core/db/enums.dart';
import 'package:thekedaar/features/attendance/data/attendance_repository.dart';
import 'package:thekedaar/features/billing/data/billing_repository.dart';
import 'package:thekedaar/features/billing/domain/document_totals.dart';
import 'package:thekedaar/features/calendar/data/calendar_repository.dart';
import 'package:thekedaar/features/expenses/data/expenses_repository.dart';
import 'package:thekedaar/features/khata/data/khata_repository.dart';
import 'package:thekedaar/features/workers/data/workers_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('calendar collects every dated record of the month', () async {
    final billing = BillingRepository(db);
    final client = await billing.saveClient(name: 'Sharma');
    final bill = await billing.saveDocument(DocumentDraft(
      kind: DocumentKind.invoice,
      clientId: client,
      date: DateTime(2026, 10, 5),
      lines: [
        DraftLine(
          lineType: LineType.lumpSum,
          name: 'Wiring',
          qtyMilli: 1000,
          ratePaise: 1000000,
        ),
      ],
    ));
    await billing.markSentIfDraft(bill);
    await billing.recordPayment(
      clientId: client,
      documentId: bill,
      amountPaise: 400000,
      mode: PaymentMode.gPay,
      date: DateTime(2026, 10, 5),
    );

    final worker = await WorkersRepository(db).addWorker(NewWorker(
      name: 'Raju',
      joinDate: DateTime(2026, 1, 1),
      wageModel: WageModel.daily,
      ratePaise: 60000,
    ));
    await KhataRepository(db).addEntry(
      workerId: worker,
      type: LedgerType.advance,
      amountPaise: 50000,
      at: DateTime(2026, 10, 5, 11),
      mode: PaymentMode.cash,
    );
    await AttendanceRepository(db).setStatus(
      workerId: worker,
      date: DateTime(2026, 10, 5),
      status: AttendanceStatus.present,
    );

    final expenses = ExpensesRepository(db);
    final category = await expenses.addCategory('Material');
    await expenses.addExpense(
      categoryId: category,
      amountPaise: 120000,
      mode: PaymentMode.cash,
      date: DateTime(2026, 10, 6),
    );
    // Next month: not in October.
    await expenses.addExpense(
      categoryId: category,
      amountPaise: 999,
      mode: PaymentMode.cash,
      date: DateTime(2026, 11, 1),
    );

    final month =
        await CalendarRepository(db).loadMonth(DateTime(2026, 10));
    final day5 = month.on('2026-10-05');
    expect(day5.map((e) => e.kind).toSet(), {
      CalendarEventKind.bill,
      CalendarEventKind.paymentIn,
      CalendarEventKind.workerPaid,
    });
    expect(month.inPaise('2026-10-05'), 400000);
    expect(month.outPaise('2026-10-05'), 50000);
    expect(month.attendance['2026-10-05']!.present, 1);

    expect(month.on('2026-10-06').single.kind, CalendarEventKind.expense);
    expect(month.outPaise('2026-10-06'), 120000);
    expect(month.events.keys, isNot(contains('2026-11-01')));
    expect(day5.firstWhere((e) => e.kind == CalendarEventKind.bill).route,
        '/doc/$bill');
  });
}
