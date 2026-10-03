import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'enums.dart';
import 'tables.dart';

part 'database.g.dart';

const databaseFileName = 'thekedaar.sqlite';

/// Absolute path of the live database file (backup snapshots and restore
/// swap work on this path).
Future<String> databaseFilePath() async =>
    p.join((await getApplicationDocumentsDirectory()).path, databaseFileName);

@DriftDatabase(tables: [
  BusinessProfiles,
  AppMeta,
  Roles,
  Units,
  ExpenseCategories,
  ItemMasters,
  BillTemplates,
  Workers,
  WageHistories,
  Attendances,
  Holidays,
  PieceWorks,
  LedgerEntries,
  Settlements,
  Clients,
  Jobs,
  Documents,
  DocumentLines,
  PaymentsReceived,
  Expenses,
  AuditLogs,
  BackupLogs,
])
class AppDatabase extends _$AppDatabase {
  /// Pass an [executor] (e.g. `NativeDatabase.memory()`) in tests.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  /// Bump on every schema change and add a step in [migration] (PRD Part F).
  static const currentSchemaVersion = 1;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
        },
      );

  static QueryExecutor _open() => driftDatabase(
        name: 'thekedaar',
        native: const DriftNativeOptions(databasePath: databaseFilePath),
      );
}
