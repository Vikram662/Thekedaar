import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/core/db/database.dart';
import 'package:thekedaar/core/db/enums.dart';
import 'package:thekedaar/features/attendance/data/attendance_repository.dart';
import 'package:thekedaar/features/billing/data/billing_repository.dart';
import 'package:thekedaar/features/billing/domain/document_totals.dart';
import 'package:thekedaar/features/khata/data/khata_repository.dart';
import 'package:thekedaar/features/reports/domain/dues_report.dart';
import 'package:thekedaar/features/workers/data/workers_repository.dart';

DateTime day(int offset) {
  final t = DateTime.now();
  return DateTime(t.year, t.month, t.day + offset);
}

void main() {
  late AppDatabase db;
  late BillingRepository billing;
  late KhataRepository khata;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    billing = BillingRepository(db);
    khata = KhataRepository(db);
  });

  tearDown(() => db.close());

  Future<String> bill(String clientId, int ratePaise, {DateTime? due}) async {
    final id = await billing.saveDocument(DocumentDraft(
      kind: DocumentKind.invoice,
      clientId: clientId,
      date: day(-20),
      dueDate: due,
      lines: [
        DraftLine(
          lineType: LineType.lumpSum,
          name: 'Work',
          qtyMilli: 1000,
          ratePaise: ratePaise,
        ),
      ],
    ));
    await billing.markSentIfDraft(id);
    return id;
  }

  Future<DuesReport> report() async => buildDuesReport(
        clients: await billing.watchClients().first,
        invoices: await billing.watchDocuments(DocumentKind.invoice).first,
        workers: await khata.watchAllBalances().first,
      );

  test('lena from clients with overdue, dena to workers', () async {
    final sharma = await billing.saveClient(name: 'Sharma');
    final gupta = await billing.saveClient(name: 'Gupta');
    await bill(sharma, 1000000, due: day(-2)); // overdue ₹10,000
    await bill(sharma, 500000, due: day(5)); // not yet due
    final guptaBill = await bill(gupta, 300000);
    await billing.recordPayment(
      clientId: gupta,
      documentId: guptaBill,
      amountPaise: 300000,
      mode: PaymentMode.cash,
      date: day(-1),
    );

    final workers = WorkersRepository(db);
    final raju = await workers.addWorker(NewWorker(
      name: 'Raju',
      joinDate: day(-10),
      wageModel: WageModel.daily,
      ratePaise: 60000,
    ));
    final mohan = await workers.addWorker(NewWorker(
      name: 'Mohan',
      joinDate: day(-10),
      wageModel: WageModel.daily,
      ratePaise: 60000,
    ));
    final attendance = AttendanceRepository(db);
    for (var d = -5; d <= -1; d++) {
      await attendance.setStatus(
          workerId: raju, date: day(d), status: AttendanceStatus.present);
    }
    // Mohan took ₹1,000 but has no attendance: he owes money.
    await khata.addEntry(
      workerId: mohan,
      type: LedgerType.advance,
      amountPaise: 100000,
      at: day(-3),
    );

    final r = await report();
    expect(r.lena.map((d) => d.name), ['Sharma', 'Mohan']);
    expect(r.lena.first.amountPaise, 1500000);
    expect(r.lena.first.overduePaise, 1000000);
    expect(r.overdueTotal, 1000000);
    expect(r.lenaTotal, 1500000 + 100000);

    expect(r.dena.single.name, 'Raju');
    expect(r.dena.single.amountPaise, 300000);
    expect(r.denaTotal, 300000);
  });

  test('client paid in advance shows under dena', () async {
    final c = await billing.saveClient(name: 'Verma');
    await billing.recordPayment(
      clientId: c,
      amountPaise: 200000,
      mode: PaymentMode.bank,
      date: day(0),
    );
    final r = await report();
    expect(r.lena, isEmpty);
    expect(r.dena.single.party, DueParty.client);
    expect(r.dena.single.amountPaise, 200000);
  });
}
