import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/core/db/database.dart';
import 'package:thekedaar/core/db/enums.dart';
import 'package:thekedaar/features/attendance/data/attendance_repository.dart';
import 'package:thekedaar/features/workers/data/workers_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('month register lists every worker with day-wise marks (AT-04)',
      () async {
    final workers = WorkersRepository(db);
    final attendance = AttendanceRepository(db);
    Future<String> add(String name, DateTime joined) =>
        workers.addWorker(NewWorker(
          name: name,
          joinDate: joined,
          wageModel: WageModel.daily,
          ratePaise: 60000,
        ));

    final raju = await add('Raju', DateTime(2026, 9, 1));
    final amit = await add('Amit', DateTime(2026, 9, 1));
    final left = await add('Left Guy', DateTime(2026, 9, 1));
    await add('Joins Later', DateTime(2026, 11, 5));

    Future<void> mark(String id, int day, AttendanceStatus s) =>
        attendance.setStatus(
            workerId: id, date: DateTime(2026, 10, day), status: s);

    await mark(raju, 1, AttendanceStatus.present);
    await mark(raju, 2, AttendanceStatus.half);
    await mark(raju, 3, AttendanceStatus.absent);
    await mark(raju, 4, AttendanceStatus.leavePaid);
    await mark(amit, 1, AttendanceStatus.present);
    await mark(left, 2, AttendanceStatus.present);
    await workers.setActive(left, false);
    await mark(raju, 1, AttendanceStatus.present); // same day again
    await attendance.setStatus(
      workerId: raju,
      date: DateTime(2026, 11, 1),
      status: AttendanceStatus.present,
    ); // other month

    final r =
        await attendance.watchMonthRegister(DateTime(2026, 10)).first;
    expect(r.days, 31);
    // Inactive worker with marks stays; future joiner is not listed.
    expect(r.workers.map((w) => w.name), ['Amit', 'Left Guy', 'Raju']);
    expect(r.marks[raju], {
      1: AttendanceStatus.present,
      2: AttendanceStatus.half,
      3: AttendanceStatus.absent,
      4: AttendanceStatus.leavePaid,
    });
    expect(r.count(raju, AttendanceStatus.present), 1);
    expect(r.paidDays(raju), 2.5); // P + ½ + paid leave
    expect(r.paidDays(amit), 1);

    final november =
        await attendance.watchMonthRegister(DateTime(2026, 11)).first;
    expect(november.marks[raju]?[1], AttendanceStatus.present);
    expect(november.workers.map((w) => w.name),
        containsAll(['Amit', 'Joins Later', 'Raju']));
    expect(november.workers.map((w) => w.name), isNot(contains('Left Guy')));
  });
}
