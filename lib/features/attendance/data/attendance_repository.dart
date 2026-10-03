import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/audit.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/db/watch.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/ids.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(ref.watch(databaseProvider)),
);

/// Key: `yyyy-MM-dd`.
final attendanceDayProvider =
    StreamProvider.family<List<AttendanceRow>, String>(
  (ref, isoDay) =>
      ref.watch(attendanceRepositoryProvider).watchDay(parseIsoDate(isoDay)),
);

typedef WorkerMonth = ({String workerId, int year, int month});

final workerMonthAttendanceProvider =
    StreamProvider.family<Map<String, Attendance>, WorkerMonth>(
  (ref, key) => ref
      .watch(attendanceRepositoryProvider)
      .watchMonth(key.workerId, DateTime(key.year, key.month)),
);

/// Key: (year, month).
final monthRegisterProvider =
    StreamProvider.family<MonthRegister, ({int year, int month})>(
  (ref, m) => ref
      .watch(attendanceRepositoryProvider)
      .watchMonthRegister(DateTime(m.year, m.month)),
);

/// All workers × all days of a month (attendance register, PRD AT-04).
class MonthRegister {
  const MonthRegister({
    required this.month,
    required this.workers,
    required this.marks,
  });

  final DateTime month;
  final List<Worker> workers;

  /// workerId → day of month → status.
  final Map<String, Map<int, AttendanceStatus>> marks;

  int get days => daysInMonth(month);

  int count(String workerId, AttendanceStatus status) =>
      (marks[workerId] ?? const {}).values.where((s) => s == status).length;

  /// Present + ½ half + paid leave (weekly off depends on the wage type,
  /// so it is not added here).
  double paidDays(String workerId) =>
      count(workerId, AttendanceStatus.present) +
      count(workerId, AttendanceStatus.half) / 2 +
      count(workerId, AttendanceStatus.leavePaid);
}

class AttendanceRow {
  const AttendanceRow({
    required this.worker,
    this.roleName,
    this.attendance,
  });

  final Worker worker;
  final String? roleName;
  final Attendance? attendance;
}

class AttendanceRepository {
  AttendanceRepository(this._db);

  final AppDatabase _db;

  /// Active workers who had joined by [date], with that day's mark.
  Stream<List<AttendanceRow>> watchDay(DateTime date) {
    final day = isoDate(date);
    final query = _db.select(_db.workers).join([
      leftOuterJoin(_db.roles, _db.roles.id.equalsExp(_db.workers.roleId)),
      leftOuterJoin(
        _db.attendances,
        _db.attendances.workerId.equalsExp(_db.workers.id) &
            _db.attendances.date.equals(day),
      ),
    ])
      ..where(_db.workers.isActive.equals(true) &
          _db.workers.joinDate.isSmallerOrEqualValue(day))
      ..orderBy([OrderingTerm.asc(_db.workers.name)]);
    return query.watch().map((rows) => [
          for (final row in rows)
            AttendanceRow(
              worker: row.readTable(_db.workers),
              roleName: row.readTableOrNull(_db.roles)?.name,
              attendance: row.readTableOrNull(_db.attendances),
            ),
        ]);
  }

  Stream<Map<String, Attendance>> watchMonth(String workerId, DateTime month) {
    final from = isoDate(DateTime(month.year, month.month));
    final to = isoDate(DateTime(month.year, month.month + 1, 0));
    final query = _db.select(_db.attendances)
      ..where((a) =>
          a.workerId.equals(workerId) & a.date.isBetweenValues(from, to));
    return query.watch().map((rows) => {for (final a in rows) a.date: a});
  }

  /// Workers who were active or have marks in [month], with every mark.
  Stream<MonthRegister> watchMonthRegister(DateTime month) {
    final from = isoDate(DateTime(month.year, month.month));
    final to = isoDate(DateTime(month.year, month.month + 1, 0));
    return watchComputed(_db, [_db.workers, _db.attendances], () async {
      final rows = await (_db.select(_db.attendances)
            ..where((a) => a.date.isBetweenValues(from, to)))
          .get();
      final marks = <String, Map<int, AttendanceStatus>>{};
      for (final a in rows) {
        (marks[a.workerId] ??= {})[parseIsoDate(a.date).day] = a.status;
      }
      final workers = await (_db.select(_db.workers)
            ..where((w) => w.joinDate.isSmallerOrEqualValue(to))
            ..orderBy([(w) => OrderingTerm.asc(w.name)]))
          .get();
      return MonthRegister(
        month: DateTime(month.year, month.month),
        workers: [
          for (final w in workers)
            if (w.isActive || marks.containsKey(w.id)) w,
        ],
        marks: marks,
      );
    });
  }

  /// Workers marked present or half today (PRD DB-03 today strip).
  Stream<List<Worker>> watchPresentOn(DateTime date) {
    final query = _db.select(_db.attendances).join([
      innerJoin(_db.workers, _db.workers.id.equalsExp(_db.attendances.workerId)),
    ])
      ..where(_db.attendances.date.equals(isoDate(date)) &
          _db.attendances.status.isIn([
            AttendanceStatus.present.name,
            AttendanceStatus.half.name,
          ]))
      ..orderBy([OrderingTerm.asc(_db.workers.name)]);
    return query
        .watch()
        .map((rows) => [for (final r in rows) r.readTable(_db.workers)]);
  }

  /// True if [date] is inside a settled period for the worker (PRD AT-06).
  Future<bool> isLocked(String workerId, DateTime date) async {
    final day = isoDate(date);
    final row = await (_db.select(_db.settlements)
          ..where((s) =>
              s.workerId.equals(workerId) &
              s.status.equalsValue(SettlementStatus.locked) &
              s.periodFrom.isSmallerOrEqualValue(day) &
              s.periodTo.isBiggerOrEqualValue(day))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// Sets a worker's mark for a day. Changing an earlier day's mark is
  /// allowed but audited (PRD I-T3); settled days are refused.
  Future<void> setStatus({
    required String workerId,
    required DateTime date,
    required AttendanceStatus status,
    int? otMilliHours,
  }) async {
    final day = isoDate(date);
    await _db.transaction(() async {
      if (await isLocked(workerId, date)) throw const PeriodLockedException();
      final existing = await (_db.select(_db.attendances)
            ..where((a) => a.workerId.equals(workerId) & a.date.equals(day)))
          .getSingleOrNull();
      final ot = status == AttendanceStatus.present ||
              status == AttendanceStatus.half
          ? (otMilliHours ?? existing?.otMilliHours ?? 0)
          : 0;
      if (existing == null) {
        await _db.into(_db.attendances).insert(AttendancesCompanion.insert(
              id: newId(),
              workerId: workerId,
              date: day,
              status: status,
              otMilliHours: Value(ot),
            ));
        return;
      }
      await (_db.update(_db.attendances)
            ..where((a) => a.id.equals(existing.id)))
          .write(AttendancesCompanion(
        status: Value(status),
        otMilliHours: Value(ot),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));
      final isPastDay = day.compareTo(isoDate(DateTime.now())) < 0;
      if (isPastDay) {
        await writeAudit(_db,
            entity: 'attendance',
            entityId: existing.id,
            action: AuditAction.update,
            before: existing.toJson(),
            after: {
              ...existing.toJson(),
              'status': status.name,
              'otMilliHours': ot,
            });
      }
    });
  }

  /// Removes a mark (back to "not marked").
  Future<void> clear(String workerId, DateTime date) async {
    final day = isoDate(date);
    await _db.transaction(() async {
      if (await isLocked(workerId, date)) throw const PeriodLockedException();
      final existing = await (_db.select(_db.attendances)
            ..where((a) => a.workerId.equals(workerId) & a.date.equals(day)))
          .getSingleOrNull();
      if (existing == null) return;
      await (_db.delete(_db.attendances)
            ..where((a) => a.id.equals(existing.id)))
          .go();
      await writeAudit(_db,
          entity: 'attendance',
          entityId: existing.id,
          action: AuditAction.delete,
          before: existing.toJson());
    });
  }

  /// PRD AT-02: marks every unmarked, unlocked worker with [status].
  /// Returns how many were marked.
  Future<int> markAllUnmarked(DateTime date, AttendanceStatus status) async {
    final rows = await watchDay(date).first;
    var count = 0;
    await _db.transaction(() async {
      for (final row in rows) {
        if (row.attendance != null) continue;
        if (await isLocked(row.worker.id, date)) continue;
        await _db.into(_db.attendances).insert(AttendancesCompanion.insert(
              id: newId(),
              workerId: row.worker.id,
              date: isoDate(date),
              status: status,
            ));
        count++;
      }
    });
    return count;
  }

  /// PRD AT-02 "Copy yesterday": copies marks from [from] for workers not
  /// yet marked on [to]. Returns how many were copied.
  Future<int> copyDay({required DateTime from, required DateTime to}) async {
    final source = {
      for (final row in await watchDay(from).first)
        if (row.attendance != null) row.worker.id: row.attendance!,
    };
    final target = await watchDay(to).first;
    var count = 0;
    await _db.transaction(() async {
      for (final row in target) {
        final copy = source[row.worker.id];
        if (row.attendance != null || copy == null) continue;
        if (await isLocked(row.worker.id, to)) continue;
        await _db.into(_db.attendances).insert(AttendancesCompanion.insert(
              id: newId(),
              workerId: row.worker.id,
              date: isoDate(to),
              status: copy.status,
              otMilliHours: Value(copy.otMilliHours),
            ));
        count++;
      }
    });
    return count;
  }
}
