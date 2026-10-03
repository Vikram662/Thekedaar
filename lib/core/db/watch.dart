import 'package:drift/drift.dart';

import 'database.dart';

/// Re-runs [compute] whenever any of [tables] changes. For values that need
/// several queries plus Dart logic (worker balance, totals).
Stream<T> watchComputed<T>(
  AppDatabase db,
  Iterable<ResultSetImplementation<dynamic, dynamic>> tables,
  Future<T> Function() compute,
) async* {
  yield await compute();
  await for (final _ in db.tableUpdates(TableUpdateQuery.onAllTables(tables))) {
    yield await compute();
  }
}
