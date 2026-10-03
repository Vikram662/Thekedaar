import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/audit.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/money.dart';

final workersRepositoryProvider = Provider<WorkersRepository>(
  (ref) => WorkersRepository(ref.watch(databaseProvider)),
);

final activeWorkersProvider = StreamProvider<List<WorkerListItem>>(
  (ref) => ref.watch(workersRepositoryProvider).watchWorkers(),
);

final inactiveWorkersProvider = StreamProvider<List<WorkerListItem>>(
  (ref) => ref.watch(workersRepositoryProvider).watchWorkers(active: false),
);

final workerProvider = StreamProvider.family<WorkerListItem?, String>(
  (ref, id) => ref.watch(workersRepositoryProvider).watchWorker(id),
);

final wageHistoryProvider = StreamProvider.family<List<WageHistory>, String>(
  (ref, workerId) =>
      ref.watch(workersRepositoryProvider).watchWageHistory(workerId),
);

final rolesProvider = StreamProvider<List<Role>>(
  (ref) => ref.watch(workersRepositoryProvider).watchRoles(),
);

class WorkerListItem {
  const WorkerListItem({required this.worker, this.roleName, this.wage});

  final Worker worker;
  final String? roleName;

  /// Wage rate in force today.
  final WageHistory? wage;
}

class NewWorker {
  const NewWorker({
    required this.name,
    required this.joinDate,
    required this.wageModel,
    required this.ratePaise,
    this.phone,
    this.roleId,
    this.upiId,
    this.otRatePaise = 0,
    this.monthlyDivisor = 30,
  });

  final String name;
  final String? phone;
  final String? roleId;
  final String? upiId;
  final DateTime joinDate;
  final WageModel wageModel;
  final int ratePaise;
  final int otRatePaise;
  final int monthlyDivisor;
}

/// `₹600/day`, `₹18,000/month`, `Piece-rate`.
String wageLabel(WageHistory? wage) {
  if (wage == null) return 'No wage set';
  return switch (wage.model) {
    WageModel.daily => '${formatPaise(wage.ratePaise)}/day',
    WageModel.monthly => '${formatPaise(wage.ratePaise)}/month',
    WageModel.piece => 'Piece-rate',
  };
}

class WorkersRepository {
  WorkersRepository(this._db);

  final AppDatabase _db;

  JoinedSelectStatement<$WorkersTable, Worker> _workerQuery() =>
      _db.select(_db.workers).join([
        leftOuterJoin(_db.roles, _db.roles.id.equalsExp(_db.workers.roleId)),
      ]);

  Future<Map<String, WageHistory>> _currentWages() async {
    final today = isoDate(DateTime.now());
    final rows = await (_db.select(_db.wageHistories)
          ..where((w) => w.effectiveFrom.isSmallerOrEqualValue(today))
          ..orderBy([(w) => OrderingTerm.asc(w.effectiveFrom)]))
        .get();
    // Later rows overwrite earlier ones → latest rate per worker.
    return {for (final w in rows) w.workerId: w};
  }

  Stream<List<WorkerListItem>> watchWorkers({bool active = true}) {
    final query = _workerQuery()
      ..where(_db.workers.isActive.equals(active))
      ..orderBy([OrderingTerm.asc(_db.workers.name)]);
    return query.watch().asyncMap((rows) async {
      final wages = await _currentWages();
      return [
        for (final row in rows)
          WorkerListItem(
            worker: row.readTable(_db.workers),
            roleName: row.readTableOrNull(_db.roles)?.name,
            wage: wages[row.readTable(_db.workers).id],
          ),
      ];
    });
  }

  Stream<WorkerListItem?> watchWorker(String id) {
    final query = _workerQuery()..where(_db.workers.id.equals(id));
    return query.watchSingleOrNull().asyncMap((row) async {
      if (row == null) return null;
      final wages = await _currentWages();
      return WorkerListItem(
        worker: row.readTable(_db.workers),
        roleName: row.readTableOrNull(_db.roles)?.name,
        wage: wages[id],
      );
    });
  }

  Stream<List<WageHistory>> watchWageHistory(String workerId) =>
      (_db.select(_db.wageHistories)
            ..where((w) => w.workerId.equals(workerId))
            ..orderBy([(w) => OrderingTerm.desc(w.effectiveFrom)]))
          .watch();

  Stream<List<Role>> watchRoles() {
    final query = _db.select(_db.roles)
      ..where((r) => r.isHidden.equals(false))
      ..orderBy([
        (r) => OrderingTerm.asc(r.sort),
        (r) => OrderingTerm.asc(r.name),
      ]);
    return query.watch();
  }

  Future<String> addRole(String name) async {
    final id = newId();
    await _db.into(_db.roles).insert(
          RolesCompanion.insert(id: id, name: name, sort: const Value(100)),
        );
    return id;
  }

  /// Saves the worker and their first wage rate (effective from joining).
  Future<String> addWorker(NewWorker input) async {
    final workerId = newId();
    final joinDate = isoDate(input.joinDate);
    await _db.transaction(() async {
      await _db.into(_db.workers).insert(
            WorkersCompanion.insert(
              id: workerId,
              name: input.name,
              phone: Value(input.phone),
              roleId: Value(input.roleId),
              upiId: Value(input.upiId),
              joinDate: joinDate,
            ),
          );
      await _db.into(_db.wageHistories).insert(
            WageHistoriesCompanion.insert(
              id: newId(),
              workerId: workerId,
              model: input.wageModel,
              ratePaise: input.ratePaise,
              otRatePaise: Value(input.otRatePaise),
              monthlyDivisor: Value(input.monthlyDivisor),
              effectiveFrom: joinDate,
            ),
          );
      await writeAudit(_db,
          entity: 'worker', entityId: workerId, action: AuditAction.create);
    });
    return workerId;
  }

  Future<void> updateWorker({
    required String id,
    required String name,
    String? phone,
    String? roleId,
    String? upiId,
  }) async {
    await _db.transaction(() async {
      final before = await (_db.select(_db.workers)
            ..where((w) => w.id.equals(id)))
          .getSingle();
      await (_db.update(_db.workers)..where((w) => w.id.equals(id))).write(
        WorkersCompanion(
          name: Value(name),
          phone: Value(phone),
          roleId: Value(roleId),
          upiId: Value(upiId),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      final after = await (_db.select(_db.workers)
            ..where((w) => w.id.equals(id)))
          .getSingle();
      await writeAudit(_db,
          entity: 'worker',
          entityId: id,
          action: AuditAction.update,
          before: before.toJson(),
          after: after.toJson());
    });
  }

  /// PRD WK-04: inactive workers keep their records and balance.
  Future<void> setActive(String id, bool active) =>
      (_db.update(_db.workers)..where((w) => w.id.equals(id))).write(
        WorkersCompanion(
          isActive: Value(active),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  /// PRD WK-03 / I-S5: a new rate from a date; older days keep the old rate.
  Future<void> changeWage({
    required String workerId,
    required WageModel model,
    required int ratePaise,
    required int otRatePaise,
    required int monthlyDivisor,
    required DateTime effectiveFrom,
  }) async {
    final from = isoDate(effectiveFrom);
    await _db.transaction(() async {
      // Same start date replaces that entry instead of stacking two.
      await (_db.delete(_db.wageHistories)
            ..where((w) => w.workerId.equals(workerId) & w.effectiveFrom.equals(from)))
          .go();
      final id = newId();
      await _db.into(_db.wageHistories).insert(
            WageHistoriesCompanion.insert(
              id: id,
              workerId: workerId,
              model: model,
              ratePaise: ratePaise,
              otRatePaise: Value(otRatePaise),
              monthlyDivisor: Value(monthlyDivisor),
              effectiveFrom: from,
            ),
          );
      await writeAudit(_db,
          entity: 'wage',
          entityId: id,
          action: AuditAction.create,
          after: {
            'workerId': workerId,
            'model': model.name,
            'ratePaise': ratePaise,
            'effectiveFrom': from,
          });
    });
  }
}
