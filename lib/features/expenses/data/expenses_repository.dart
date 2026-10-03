import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/audit.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/ids.dart';

final expensesRepositoryProvider = Provider<ExpensesRepository>(
  (ref) => ExpensesRepository(ref.watch(databaseProvider)),
);

final expenseCategoriesProvider = StreamProvider<List<ExpenseCategory>>(
  (ref) => ref.watch(expensesRepositoryProvider).watchCategories(),
);

typedef ExpenseMonth = ({int year, int month});

final monthExpensesProvider =
    StreamProvider.family<List<ExpenseItem>, ExpenseMonth>(
  (ref, m) => ref
      .watch(expensesRepositoryProvider)
      .watchExpenses(DateTime(m.year, m.month)),
);

final suppliersProvider = StreamProvider<List<SupplierBalance>>(
  (ref) => ref.watch(expensesRepositoryProvider).watchSuppliers(),
);

final supplierProvider = StreamProvider.family<SupplierBalance?, String>(
  (ref, id) => ref.watch(expensesRepositoryProvider).watchSuppliers().map(
        (all) => all.where((s) => s.supplier.id == id).firstOrNull,
      ),
);

final supplierEntriesProvider =
    StreamProvider.family<List<SupplierEntry>, String>(
  (ref, id) => ref.watch(expensesRepositoryProvider).watchSupplierEntries(id),
);

class ExpenseItem {
  const ExpenseItem({required this.expense, required this.categoryName});

  final Expense expense;
  final String categoryName;
}

class SupplierBalance {
  const SupplierBalance({
    required this.supplier,
    required this.purchasedPaise,
    required this.paidPaise,
  });

  final Supplier supplier;
  final int purchasedPaise;
  final int paidPaise;

  /// Positive: you owe the supplier (dena). Negative: paid in advance.
  int get duePaise => purchasedPaise - paidPaise;
}

/// Total per category, biggest first.
List<({String category, int totalPaise})> totalsByCategory(
  Iterable<ExpenseItem> items,
) {
  final totals = <String, int>{};
  for (final item in items) {
    totals.update(
      item.categoryName,
      (v) => v + item.expense.amountPaise,
      ifAbsent: () => item.expense.amountPaise,
    );
  }
  final list = [
    for (final e in totals.entries) (category: e.key, totalPaise: e.value),
  ]..sort((a, b) => b.totalPaise.compareTo(a.totalPaise));
  return list;
}

class ExpensesRepository {
  ExpensesRepository(this._db);

  final AppDatabase _db;

  // ─── Expenses (PRD EX-01) ─────────────────────────────────────────────────

  Stream<List<ExpenseCategory>> watchCategories() =>
      (_db.select(_db.expenseCategories)
            ..where((c) => c.isHidden.equals(false))
            ..orderBy([
              (c) => OrderingTerm.asc(c.sort),
              (c) => OrderingTerm.asc(c.name),
            ]))
          .watch();

  Future<String> addCategory(String name) async {
    final id = newId();
    await _db.into(_db.expenseCategories).insert(
          ExpenseCategoriesCompanion.insert(
            id: id,
            name: name,
            sort: const Value(100),
          ),
        );
    return id;
  }

  Future<String> addExpense({
    required String categoryId,
    required int amountPaise,
    required PaymentMode mode,
    required DateTime date,
    String? remarks,
  }) async {
    if (amountPaise <= 0) throw ArgumentError('Amount must be more than 0');
    final id = newId();
    await _db.into(_db.expenses).insert(ExpensesCompanion.insert(
          id: id,
          categoryId: categoryId,
          amountPaise: amountPaise,
          mode: mode,
          date: isoDate(date),
          remarks: Value(remarks),
        ));
    await writeAudit(_db,
        entity: 'expense', entityId: id, action: AuditAction.create);
    return id;
  }

  Future<void> deleteExpense(String id) async {
    await _db.transaction(() async {
      final before = await (_db.select(_db.expenses)
            ..where((e) => e.id.equals(id)))
          .getSingle();
      await (_db.delete(_db.expenses)..where((e) => e.id.equals(id))).go();
      await writeAudit(_db,
          entity: 'expense',
          entityId: id,
          action: AuditAction.delete,
          before: before.toJson());
    });
  }

  Stream<List<ExpenseItem>> watchExpenses(DateTime month) {
    final from = isoDate(DateTime(month.year, month.month));
    final to = isoDate(DateTime(month.year, month.month + 1, 0));
    final query = _db.select(_db.expenses).join([
      innerJoin(_db.expenseCategories,
          _db.expenseCategories.id.equalsExp(_db.expenses.categoryId)),
    ])
      ..where(_db.expenses.date.isBetweenValues(from, to))
      ..orderBy([
        OrderingTerm.desc(_db.expenses.date),
        OrderingTerm.desc(_db.expenses.createdAt),
      ]);
    return query.watch().map((rows) => [
          for (final row in rows)
            ExpenseItem(
              expense: row.readTable(_db.expenses),
              categoryName: row.readTable(_db.expenseCategories).name,
            ),
        ]);
  }

  // ─── Suppliers (PRD EX-02) ────────────────────────────────────────────────

  Stream<List<SupplierBalance>> watchSuppliers() {
    return _db.customSelect(
      '''
      SELECT s.*,
        COALESCE((SELECT SUM(l.amount_paise) FROM supplier_ledger l
          WHERE l.supplier_id = s.id AND l.entry_type = 'purchase'), 0) AS purchased,
        COALESCE((SELECT SUM(l.amount_paise) FROM supplier_ledger l
          WHERE l.supplier_id = s.id AND l.entry_type = 'payment'), 0) AS paid
      FROM suppliers s
      ORDER BY s.name COLLATE NOCASE
      ''',
      readsFrom: {_db.suppliers, _db.supplierLedger},
    ).watch().map((rows) => [
          for (final row in rows)
            SupplierBalance(
              supplier: _db.suppliers.map(row.data),
              purchasedPaise: row.read<int>('purchased'),
              paidPaise: row.read<int>('paid'),
            ),
        ]);
  }

  Future<String> saveSupplier({
    String? id,
    required String name,
    String? phone,
    String? address,
  }) async {
    if (id == null) {
      final newSupplierId = newId();
      await _db.into(_db.suppliers).insert(SuppliersCompanion.insert(
            id: newSupplierId,
            name: name,
            phone: Value(phone),
            address: Value(address),
          ));
      return newSupplierId;
    }
    await (_db.update(_db.suppliers)..where((s) => s.id.equals(id))).write(
      SuppliersCompanion(
        name: Value(name),
        phone: Value(phone),
        address: Value(address),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    return id;
  }

  Stream<List<SupplierEntry>> watchSupplierEntries(String supplierId) =>
      (_db.select(_db.supplierLedger)
            ..where((l) => l.supplierId.equals(supplierId))
            ..orderBy([
              (l) => OrderingTerm.desc(l.date),
              (l) => OrderingTerm.desc(l.createdAt),
            ]))
          .watch();

  Future<String> addSupplierEntry({
    required String supplierId,
    required SupplierEntryType type,
    required int amountPaise,
    required DateTime date,
    PaymentMode? mode,
    String? billNo,
    String? remarks,
  }) async {
    if (amountPaise <= 0) throw ArgumentError('Amount must be more than 0');
    final id = newId();
    await _db.into(_db.supplierLedger).insert(SupplierLedgerCompanion.insert(
          id: id,
          supplierId: supplierId,
          entryType: type,
          amountPaise: amountPaise,
          date: isoDate(date),
          mode: Value(mode),
          billNo: Value(billNo),
          remarks: Value(remarks),
        ));
    await writeAudit(_db,
        entity: 'supplier_entry',
        entityId: id,
        action: AuditAction.create,
        after: {
          'supplierId': supplierId,
          'type': type.name,
          'amountPaise': amountPaise,
        });
    return id;
  }

  Future<void> deleteSupplierEntry(String id) async {
    await _db.transaction(() async {
      final before = await (_db.select(_db.supplierLedger)
            ..where((l) => l.id.equals(id)))
          .getSingle();
      await (_db.delete(_db.supplierLedger)..where((l) => l.id.equals(id)))
          .go();
      await writeAudit(_db,
          entity: 'supplier_entry',
          entityId: id,
          action: AuditAction.delete,
          before: before.toJson());
    });
  }
}
