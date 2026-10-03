import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/core/db/database.dart';
import 'package:thekedaar/core/db/enums.dart';
import 'package:thekedaar/features/expenses/data/expenses_repository.dart';
import 'package:thekedaar/features/reports/domain/dues_report.dart';

void main() {
  late AppDatabase db;
  late ExpensesRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ExpensesRepository(db);
  });

  tearDown(() => db.close());

  test('expenses by month with category totals (EX-01)', () async {
    final petrol = await repo.addCategory('Petrol');
    final food = await repo.addCategory('Food');
    await repo.addExpense(
        categoryId: petrol,
        amountPaise: 50000,
        mode: PaymentMode.cash,
        date: DateTime(2026, 10, 2));
    await repo.addExpense(
        categoryId: petrol,
        amountPaise: 30000,
        mode: PaymentMode.gPay,
        date: DateTime(2026, 10, 20));
    await repo.addExpense(
        categoryId: food,
        amountPaise: 12000,
        mode: PaymentMode.cash,
        date: DateTime(2026, 10, 31));
    await repo.addExpense(
        categoryId: food,
        amountPaise: 99900,
        mode: PaymentMode.cash,
        date: DateTime(2026, 11, 1)); // next month

    final october = await repo.watchExpenses(DateTime(2026, 10)).first;
    expect(october, hasLength(3));
    final totals = totalsByCategory(october);
    expect(totals.first.category, 'Petrol');
    expect(totals.first.totalPaise, 80000);
    expect(totals.last.totalPaise, 12000);

    await repo.deleteExpense(october.first.expense.id);
    expect(await repo.watchExpenses(DateTime(2026, 10)).first, hasLength(2));
  });

  test('supplier due = purchases − payments (EX-02)', () async {
    final shop = await repo.saveSupplier(name: 'Gupta Hardware');
    await repo.addSupplierEntry(
      supplierId: shop,
      type: SupplierEntryType.purchase,
      amountPaise: 2500000,
      date: DateTime(2026, 10, 1),
      billNo: 'G-101',
    );
    await repo.addSupplierEntry(
      supplierId: shop,
      type: SupplierEntryType.payment,
      amountPaise: 1000000,
      date: DateTime(2026, 10, 5),
      mode: PaymentMode.bank,
    );
    final advanceShop = await repo.saveSupplier(name: 'Sharma Paints');
    await repo.addSupplierEntry(
      supplierId: advanceShop,
      type: SupplierEntryType.payment,
      amountPaise: 300000,
      date: DateTime(2026, 10, 5),
    );

    final balances = await repo.watchSuppliers().first;
    final gupta = balances.firstWhere((s) => s.supplier.id == shop);
    expect(gupta.purchasedPaise, 2500000);
    expect(gupta.paidPaise, 1000000);
    expect(gupta.duePaise, 1500000);

    final report = buildDuesReport(
      clients: const [],
      invoices: const [],
      workers: const [],
      suppliers: balances,
    );
    expect(report.dena.single.party, DueParty.supplier);
    expect(report.denaTotal, 1500000);
    expect(report.lena.single.name, 'Sharma Paints'); // advance paid
    expect(report.lenaTotal, 300000);

    final entries = await repo.watchSupplierEntries(shop).first;
    expect(entries, hasLength(2));
    await repo.deleteSupplierEntry(
        entries.firstWhere((e) => e.entryType == SupplierEntryType.payment).id);
    final after = (await repo.watchSuppliers().first)
        .firstWhere((s) => s.supplier.id == shop);
    expect(after.duePaise, 2500000);
  });
}
