import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/core/db/database.dart';
import 'package:thekedaar/core/db/enums.dart';
import 'package:thekedaar/features/billing/data/billing_repository.dart';
import 'package:thekedaar/features/billing/domain/document_totals.dart';
import 'package:thekedaar/features/expenses/data/expenses_repository.dart';
import 'package:thekedaar/features/jobs/data/jobs_repository.dart';
import 'package:thekedaar/features/khata/data/khata_repository.dart';
import 'package:thekedaar/features/workers/data/workers_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('job shows its bills, payments, expenses and profit (JB-01, EX-03)',
      () async {
    final billing = BillingRepository(db);
    final jobs = JobsRepository(db);
    final expenses = ExpensesRepository(db);

    final client = await billing.saveClient(name: 'Sharma');
    final jobId = await jobs.saveJob(
      clientId: client,
      title: '2BHK wiring',
      status: JobStatus.inProgress,
      contractValuePaise: 10000000,
    );

    DocumentDraft draft({String? job, int rate = 5000000}) => DocumentDraft(
          kind: DocumentKind.invoice,
          clientId: client,
          jobId: job,
          date: DateTime(2026, 10, 3),
          lines: [
            DraftLine(
              lineType: LineType.lumpSum,
              name: 'Stage 1',
              qtyMilli: 1000,
              ratePaise: rate,
            ),
          ],
        );

    final linked = await billing.saveDocument(draft(job: jobId));
    await billing.markSentIfDraft(linked);
    final draftOnly = await billing.saveDocument(draft(job: jobId, rate: 99900));
    await billing.saveDocument(draft()); // other bill, no job
    await billing.recordPayment(
      clientId: client,
      documentId: linked,
      amountPaise: 2000000,
      mode: PaymentMode.bank,
      date: DateTime(2026, 10, 4),
    );

    final category = await expenses.addCategory('Material');
    await expenses.addExpense(
      categoryId: category,
      amountPaise: 1200000,
      mode: PaymentMode.cash,
      date: DateTime(2026, 10, 3),
      jobId: jobId,
      photoName: 'bill-photo.jpg',
    );
    await expenses.addExpense(
      categoryId: category,
      amountPaise: 777700,
      mode: PaymentMode.cash,
      date: DateTime(2026, 10, 3),
    ); // not for this job

    final worker = await WorkersRepository(db).addWorker(NewWorker(
      name: 'Raju',
      joinDate: DateTime(2026, 9, 1),
      wageModel: WageModel.piece,
      ratePaise: 0,
    ));
    await KhataRepository(db).addPieceWork(
      workerId: worker,
      date: DateTime(2026, 10, 3),
      description: 'Light points',
      qtyMilli: 20000,
      ratePaise: 15000,
      jobId: jobId,
    );

    final d = (await jobs.watchJob(jobId).first)!;
    expect(d.client.name, 'Sharma');
    expect(d.bills.map((b) => b.id), containsAll([linked, draftOnly]));
    expect(d.billedPaise, 5000000); // draft not counted
    expect(d.receivedPaise, 2000000);
    expect(d.expensesPaise, 1200000);
    expect(d.piecePaise, 300000);
    expect(d.profitPaise, 5000000 - 1200000 - 300000);
    expect(d.expenses.single.photoPath, 'bill-photo.jpg');

    final listed = await expenses.watchExpenses(DateTime(2026, 10)).first;
    expect(listed.where((e) => e.jobTitle == '2BHK wiring'), hasLength(1));

    // A bill converted from a job's quotation stays on the job.
    final quote = await billing.saveDocument(DocumentDraft(
      kind: DocumentKind.quotation,
      clientId: client,
      jobId: jobId,
      date: DateTime(2026, 10, 3),
      lines: draft().lines,
    ));
    final converted = await billing.convertToInvoice(quote);
    final invoice = (await billing.watchDocument(converted).first)!;
    expect(invoice.document.jobId, jobId);
  });

  test('job list and status change', () async {
    final client = await BillingRepository(db).saveClient(name: 'Gupta');
    final jobs = JobsRepository(db);
    final id = await jobs.saveJob(
      clientId: client,
      title: 'Shop tiles',
      status: JobStatus.planned,
    );
    await jobs.setStatus(id, JobStatus.completed);
    final list = await jobs.watchJobs().first;
    expect(list.single.clientName, 'Gupta');
    expect(list.single.job.status, JobStatus.completed);
  });
}
