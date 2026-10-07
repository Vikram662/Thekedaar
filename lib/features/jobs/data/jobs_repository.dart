import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/audit.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/db/watch.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/ids.dart';

final jobsRepositoryProvider = Provider<JobsRepository>(
  (ref) => JobsRepository(ref.watch(databaseProvider)),
);

final jobsProvider = StreamProvider<List<JobListItem>>(
  (ref) => ref.watch(jobsRepositoryProvider).watchJobs(),
);

final jobDetailProvider = StreamProvider.family<JobDetail?, String>(
  (ref, id) => ref.watch(jobsRepositoryProvider).watchJob(id),
);

String jobStatusLabel(JobStatus status) => switch (status) {
      JobStatus.planned => tr('Planned'),
      JobStatus.inProgress => tr('In progress'),
      JobStatus.completed => tr('Completed'),
    };

class JobListItem {
  const JobListItem({required this.job, required this.clientName});

  final Job job;
  final String clientName;
}

/// PRD JB-01 / EX-03: a site with its bills and expenses.
class JobDetail {
  const JobDetail({
    required this.job,
    required this.client,
    required this.billedPaise,
    required this.receivedPaise,
    required this.expensesPaise,
    required this.piecePaise,
    required this.bills,
    required this.expenses,
  });

  final Job job;
  final Client client;

  /// Non-cancelled, non-draft bills linked to this job.
  final int billedPaise;
  final int receivedPaise;
  final int expensesPaise;

  /// Piece work booked against this job.
  final int piecePaise;
  final List<BillDocument> bills;
  final List<Expense> expenses;

  /// Billed − expenses − piece work. Daily-wage labour is not included yet.
  int get profitPaise => billedPaise - expensesPaise - piecePaise;
}

class JobsRepository {
  JobsRepository(this._db);

  final AppDatabase _db;

  Stream<List<JobListItem>> watchJobs() {
    final query = _db.select(_db.jobs).join([
      innerJoin(_db.clients, _db.clients.id.equalsExp(_db.jobs.clientId)),
    ])
      ..orderBy([
        OrderingTerm.asc(_db.jobs.status),
        OrderingTerm.desc(_db.jobs.createdAt),
      ]);
    return query.watch().map((rows) => [
          for (final row in rows)
            JobListItem(
              job: row.readTable(_db.jobs),
              clientName: row.readTable(_db.clients).name,
            ),
        ]);
  }

  Stream<JobDetail?> watchJob(String id) => watchComputed(
        _db,
        [
          _db.jobs,
          _db.documents,
          _db.paymentsReceived,
          _db.expenses,
          _db.pieceWorks,
        ],
        () async {
          final job = await (_db.select(_db.jobs)
                ..where((j) => j.id.equals(id)))
              .getSingleOrNull();
          if (job == null) return null;
          final client = await (_db.select(_db.clients)
                ..where((c) => c.id.equals(job.clientId)))
              .getSingle();
          final bills = await (_db.select(_db.documents)
                ..where((d) =>
                    d.jobId.equals(id) &
                    d.kind.equalsValue(DocumentKind.invoice))
                ..orderBy([(d) => OrderingTerm.desc(d.date)]))
              .get();
          final counted = bills.where((b) =>
              b.status != DocumentStatus.draft &&
              b.status != DocumentStatus.cancelled);
          final billIds = [for (final b in counted) b.id];
          final received = billIds.isEmpty
              ? 0
              : (await (_db.select(_db.paymentsReceived)
                        ..where((p) => p.documentId.isIn(billIds)))
                      .get())
                  .fold(0, (sum, p) => sum + p.amountPaise);
          final expenses = await (_db.select(_db.expenses)
                ..where((e) => e.jobId.equals(id))
                ..orderBy([(e) => OrderingTerm.desc(e.date)]))
              .get();
          final pieces = await (_db.select(_db.pieceWorks)
                ..where((p) => p.jobId.equals(id)))
              .get();
          return JobDetail(
            job: job,
            client: client,
            billedPaise: counted.fold(0, (sum, b) => sum + b.totalPaise),
            receivedPaise: received,
            expensesPaise: expenses.fold(0, (sum, e) => sum + e.amountPaise),
            piecePaise: pieces.fold(0, (sum, p) => sum + p.amountPaise),
            bills: bills,
            expenses: expenses,
          );
        },
      );

  Future<String> saveJob({
    String? id,
    required String clientId,
    required String title,
    String? siteAddress,
    required JobStatus status,
    int? contractValuePaise,
  }) async {
    if (id == null) {
      final jobId = newId();
      await _db.into(_db.jobs).insert(JobsCompanion.insert(
            id: jobId,
            clientId: clientId,
            title: title,
            siteAddress: Value(siteAddress),
            status: status,
            contractValuePaise: Value(contractValuePaise),
          ));
      await writeAudit(_db,
          entity: 'job', entityId: jobId, action: AuditAction.create);
      return jobId;
    }
    await (_db.update(_db.jobs)..where((j) => j.id.equals(id))).write(
      JobsCompanion(
        clientId: Value(clientId),
        title: Value(title),
        siteAddress: Value(siteAddress),
        status: Value(status),
        contractValuePaise: Value(contractValuePaise),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    return id;
  }

  Future<void> setStatus(String id, JobStatus status) =>
      (_db.update(_db.jobs)..where((j) => j.id.equals(id))).write(
        JobsCompanion(
          status: Value(status),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
}
