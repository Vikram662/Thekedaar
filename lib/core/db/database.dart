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
  Suppliers,
  SupplierLedger,
  AuditLogs,
  BackupLogs,
])
class AppDatabase extends _$AppDatabase {
  /// Pass an [executor] (e.g. `NativeDatabase.memory()`) in tests.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  /// Bump on every schema change and add a step in [migration] (PRD Part F).
  ///
  /// v1: first release. v2: suppliers + supplier khata.
  static const currentSchemaVersion = 2;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(suppliers);
            await m.createTable(supplierLedger);
          }
        },
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
