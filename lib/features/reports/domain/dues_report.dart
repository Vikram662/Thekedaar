import '../../../core/db/enums.dart';
import '../../../core/utils/dates.dart';
import '../../billing/data/billing_repository.dart';
import '../../expenses/data/expenses_repository.dart';
import '../../khata/data/khata_repository.dart';

enum DueParty { client, worker, supplier }

/// One person in the Lena (to receive) or Dena (to pay) list.
class DueItem {
  const DueItem({
    required this.party,
    required this.id,
    required this.name,
    required this.amountPaise,
    this.overduePaise = 0,
    this.phone,
  });

  final DueParty party;
  final String id;
  final String name;
  final int amountPaise;

  /// Part of [amountPaise] on bills whose due date has passed.
  final int overduePaise;
  final String? phone;
}

class DuesReport {
  const DuesReport({required this.lena, required this.dena});

  /// Money to receive: clients' pending bills, workers who took extra.
  final List<DueItem> lena;

  /// Money to pay: workers' balances, supplier dues, client advances.
  final List<DueItem> dena;

  int get lenaTotal => lena.fold(0, (sum, d) => sum + d.amountPaise);
  int get denaTotal => dena.fold(0, (sum, d) => sum + d.amountPaise);
  int get overdueTotal => lena.fold(0, (sum, d) => sum + d.overduePaise);
}

DuesReport buildDuesReport({
  required List<ClientBalance> clients,
  required List<DocumentListItem> invoices,
  required List<WorkerBalance> workers,
  List<SupplierBalance> suppliers = const [],
  DateTime? today,
}) {
  final todayIso = isoDate(today ?? DateTime.now());
  final overdueByClient = <String, int>{};
  for (final bill in invoices) {
    final doc = bill.document;
    final open = doc.status == DocumentStatus.sent ||
        doc.status == DocumentStatus.partiallyPaid;
    final due = doc.dueDate;
    if (!open || due == null || due.compareTo(todayIso) >= 0) continue;
    if (bill.balancePaise <= 0) continue;
    overdueByClient.update(
      doc.clientId,
      (v) => v + bill.balancePaise,
      ifAbsent: () => bill.balancePaise,
    );
  }

  final lena = <DueItem>[];
  final dena = <DueItem>[];
  for (final c in clients) {
    final amount = c.outstandingPaise;
    if (amount > 0) {
      final overdue = overdueByClient[c.client.id] ?? 0;
      lena.add(DueItem(
        party: DueParty.client,
        id: c.client.id,
        name: c.client.name,
        amountPaise: amount,
        overduePaise: overdue > amount ? amount : overdue,
        phone: c.client.phone,
      ));
    } else if (amount < 0) {
      dena.add(DueItem(
        party: DueParty.client,
        id: c.client.id,
        name: c.client.name,
        amountPaise: -amount,
        phone: c.client.phone,
      ));
    }
  }
  for (final w in workers) {
    final balance = w.balancePaise;
    if (balance == 0) continue;
    final item = DueItem(
      party: DueParty.worker,
      id: w.worker.id,
      name: w.worker.name,
      amountPaise: balance.abs(),
      phone: w.worker.phone,
    );
    (balance > 0 ? dena : lena).add(item);
  }
  for (final s in suppliers) {
    final due = s.duePaise;
    if (due == 0) continue;
    final item = DueItem(
      party: DueParty.supplier,
      id: s.supplier.id,
      name: s.supplier.name,
      amountPaise: due.abs(),
      phone: s.supplier.phone,
    );
    (due > 0 ? dena : lena).add(item);
  }
  int byAmount(DueItem a, DueItem b) => b.amountPaise.compareTo(a.amountPaise);
  lena.sort(byAmount);
  dena.sort(byAmount);
  return DuesReport(lena: lena, dena: dena);
}
