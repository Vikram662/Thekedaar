import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/db/watch.dart';
import '../../../core/utils/dates.dart';

/// What happened on a day, for the business calendar.
enum CalendarEventKind {
  bill,
  quotation,
  paymentIn,
  workerPaid,
  workerOther,
  pieceWork,
  settlement,
  expense,
  purchase,
  supplierPaid,
  holiday,
}

/// Which way the money moved, for colour and sign.
enum MoneyFlow { incoming, outgoing, none }

class CalendarEvent {
  const CalendarEvent({
    required this.kind,
    required this.date,
    required this.title,
    this.subtitle,
    this.amountPaise,
    this.flow = MoneyFlow.none,
    this.route,
    this.sortKey = 0,
  });

  final CalendarEventKind kind;

  /// 'yyyy-MM-dd'.
  final String date;
  final String title;
  final String? subtitle;
  final int? amountPaise;
  final MoneyFlow flow;

  /// Screen to open when tapped; null for view-only rows.
  final String? route;

  /// Time of day (ms) when known, so entries keep their order.
  final int sortKey;
}

/// Attendance totals for one day (all workers).
class DayAttendance {
  const DayAttendance({this.present = 0, this.half = 0, this.absent = 0});

  final int present;
  final int half;
  final int absent;

  bool get isEmpty => present == 0 && half == 0 && absent == 0;
}

class CalendarMonth {
  const CalendarMonth({
    required this.month,
    required this.events,
    required this.attendance,
  });

  final DateTime month;

  /// Date → events, newest first within the day.
  final Map<String, List<CalendarEvent>> events;
  final Map<String, DayAttendance> attendance;

  List<CalendarEvent> on(String date) => events[date] ?? const [];

  int inPaise(String date) => on(date)
      .where((e) => e.flow == MoneyFlow.incoming)
      .fold(0, (sum, e) => sum + (e.amountPaise ?? 0));

  int outPaise(String date) => on(date)
      .where((e) => e.flow == MoneyFlow.outgoing)
      .fold(0, (sum, e) => sum + (e.amountPaise ?? 0));
}

typedef CalendarMonthKey = ({int year, int month});

final calendarMonthProvider =
    StreamProvider.family<CalendarMonth, CalendarMonthKey>(
  (ref, key) => CalendarRepository(ref.watch(databaseProvider))
      .watchMonth(DateTime(key.year, key.month)),
);

/// Reads every dated record of a month (bills, payments, khata, expenses,
/// suppliers, holidays, attendance) into one view-only calendar.
class CalendarRepository {
  CalendarRepository(this._db);

  final AppDatabase _db;

  Stream<CalendarMonth> watchMonth(DateTime month) => watchComputed(
        _db,
        [
          _db.documents,
          _db.paymentsReceived,
          _db.ledgerEntries,
          _db.pieceWorks,
          _db.settlements,
          _db.expenses,
          _db.supplierLedger,
          _db.holidays,
          _db.attendances,
        ],
        () => loadMonth(month),
      );

  Future<CalendarMonth> loadMonth(DateTime month) async {
    final first = DateTime(month.year, month.month);
    final next = DateTime(month.year, month.month + 1);
    final from = isoDate(first);
    final to = isoDate(DateTime(month.year, month.month + 1, 0));
    final fromMs = first.millisecondsSinceEpoch;
    final toMs = next.millisecondsSinceEpoch;
    final range = [Variable.withString(from), Variable.withString(to)];
    final msRange = [Variable.withInt(fromMs), Variable.withInt(toMs)];

    final events = <CalendarEvent>[];

    Future<List<QueryRow>> rows(String sql, List<Variable> vars) =>
        _db.customSelect(sql, variables: vars).get();

    // Bills and quotations (drafts too; cancelled ones are skipped).
    for (final r in await rows('''
      SELECT d.id, d.kind, d.number, d.status, d.date, d.total_paise,
             d.created_at, c.name AS client
      FROM documents d JOIN clients c ON c.id = d.client_id
      WHERE d.date BETWEEN ? AND ? AND d.status != 'cancelled'
    ''', range)) {
      final isBill = r.read<String>('kind') == DocumentKind.invoice.name;
      final status = r.read<String>('status');
      events.add(CalendarEvent(
        kind: isBill ? CalendarEventKind.bill : CalendarEventKind.quotation,
        date: r.read<String>('date'),
        title: '${isBill ? 'Bill' : 'Quotation'} ${r.read<String>('number')}',
        subtitle: '${r.read<String>('client')}'
            '${status == DocumentStatus.draft.name ? ' · Draft' : ''}',
        amountPaise: r.read<int>('total_paise'),
        route: Routes.document(r.read<String>('id')),
        sortKey: r.read<int>('created_at'),
      ));
    }

    // Payments received from clients.
    for (final r in await rows('''
      SELECT p.client_id, p.document_id, p.amount_paise, p.mode, p.date,
             p.created_at, c.name AS client
      FROM payments_received p JOIN clients c ON c.id = p.client_id
      WHERE p.date BETWEEN ? AND ?
    ''', range)) {
      final docId = r.readNullable<String>('document_id');
      events.add(CalendarEvent(
        kind: CalendarEventKind.paymentIn,
        date: r.read<String>('date'),
        title: 'Payment received',
        subtitle: '${r.read<String>('client')} · ${_mode(r.read<String>('mode'))}',
        amountPaise: r.read<int>('amount_paise'),
        flow: MoneyFlow.incoming,
        route: docId != null
            ? Routes.document(docId)
            : Routes.client(r.read<String>('client_id')),
        sortKey: r.read<int>('created_at'),
      ));
    }

    // Worker khata: advances, payments, bonus, deductions, EMI, reversals.
    for (final r in await rows('''
      SELECT l.worker_id, l.entry_type, l.amount_paise, l.at, l.remarks,
             w.name AS worker
      FROM ledger_entries l JOIN workers w ON w.id = l.worker_id
      WHERE l.at >= ? AND l.at < ? AND l.entry_type != 'carryForward'
    ''', msRange)) {
      final type = LedgerType.values.byName(r.read<String>('entry_type'));
      final at = DateTime.fromMillisecondsSinceEpoch(r.read<int>('at'));
      final paid = type == LedgerType.advance || type == LedgerType.payment;
      final remarks = r.readNullable<String>('remarks');
      events.add(CalendarEvent(
        kind: paid
            ? CalendarEventKind.workerPaid
            : CalendarEventKind.workerOther,
        date: isoDate(at),
        title: '${_ledgerLabel(type)} · ${r.read<String>('worker')}',
        subtitle: remarks,
        amountPaise: r.read<int>('amount_paise'),
        flow: paid ? MoneyFlow.outgoing : MoneyFlow.none,
        route: Routes.worker(r.read<String>('worker_id')),
        sortKey: at.millisecondsSinceEpoch,
      ));
    }

    // Piece-rate work done.
    for (final r in await rows('''
      SELECT p.worker_id, p.date, p.description, p.amount_paise, p.created_at,
             w.name AS worker
      FROM piece_works p JOIN workers w ON w.id = p.worker_id
      WHERE p.date BETWEEN ? AND ?
    ''', range)) {
      events.add(CalendarEvent(
        kind: CalendarEventKind.pieceWork,
        date: r.read<String>('date'),
        title: 'Piece work · ${r.read<String>('worker')}',
        subtitle: r.read<String>('description'),
        amountPaise: r.read<int>('amount_paise'),
        route: Routes.worker(r.read<String>('worker_id')),
        sortKey: r.read<int>('created_at'),
      ));
    }

    // Settlements, on the day they were made.
    for (final r in await rows('''
      SELECT s.worker_id, s.paid_paise, s.status, s.created_at,
             s.period_from, s.period_to, w.name AS worker
      FROM settlements s JOIN workers w ON w.id = s.worker_id
      WHERE s.created_at >= ? AND s.created_at < ?
    ''', msRange)) {
      final at = DateTime.fromMillisecondsSinceEpoch(r.read<int>('created_at'));
      final reversed = r.read<String>('status') == SettlementStatus.reversed.name;
      events.add(CalendarEvent(
        kind: CalendarEventKind.settlement,
        date: isoDate(at),
        title: 'Settlement · ${r.read<String>('worker')}',
        subtitle: '${r.read<String>('period_from')} to '
            '${r.read<String>('period_to')}${reversed ? ' · Reversed' : ''}',
        amountPaise: r.read<int>('paid_paise'),
        flow: reversed ? MoneyFlow.none : MoneyFlow.outgoing,
        route: Routes.worker(r.read<String>('worker_id')),
        sortKey: at.millisecondsSinceEpoch,
      ));
    }

    // Expenses (kharcha).
    for (final r in await rows('''
      SELECT e.amount_paise, e.mode, e.date, e.remarks, e.job_id, e.created_at,
             c.name AS category
      FROM expenses e JOIN expense_categories c ON c.id = e.category_id
      WHERE e.date BETWEEN ? AND ?
    ''', range)) {
      final jobId = r.readNullable<String>('job_id');
      final remarks = r.readNullable<String>('remarks');
      events.add(CalendarEvent(
        kind: CalendarEventKind.expense,
        date: r.read<String>('date'),
        title: 'Expense · ${r.read<String>('category')}',
        subtitle: [
          _mode(r.read<String>('mode')),
          if (remarks != null && remarks.isNotEmpty) remarks,
        ].join(' · '),
        amountPaise: r.read<int>('amount_paise'),
        flow: MoneyFlow.outgoing,
        route: jobId != null ? Routes.job(jobId) : Routes.expenses,
        sortKey: r.read<int>('created_at'),
      ));
    }

    // Supplier purchases and payments.
    for (final r in await rows('''
      SELECT l.supplier_id, l.entry_type, l.amount_paise, l.date, l.bill_no,
             l.created_at, s.name AS supplier
      FROM supplier_ledger l JOIN suppliers s ON s.id = l.supplier_id
      WHERE l.date BETWEEN ? AND ?
    ''', range)) {
      final payment =
          r.read<String>('entry_type') == SupplierEntryType.payment.name;
      final billNo = r.readNullable<String>('bill_no');
      events.add(CalendarEvent(
        kind: payment
            ? CalendarEventKind.supplierPaid
            : CalendarEventKind.purchase,
        date: r.read<String>('date'),
        title: '${payment ? 'Paid supplier' : 'Purchase'} · '
            '${r.read<String>('supplier')}',
        subtitle: billNo == null || billNo.isEmpty ? null : 'Bill $billNo',
        amountPaise: r.read<int>('amount_paise'),
        flow: payment ? MoneyFlow.outgoing : MoneyFlow.none,
        route: Routes.supplier(r.read<String>('supplier_id')),
        sortKey: r.read<int>('created_at'),
      ));
    }

    // Holidays.
    for (final r in await rows(
        'SELECT date, name FROM holidays WHERE date BETWEEN ? AND ?', range)) {
      events.add(CalendarEvent(
        kind: CalendarEventKind.holiday,
        date: r.read<String>('date'),
        title: 'Holiday · ${r.read<String>('name')}',
        sortKey: 1 << 52, // top of the day
      ));
    }

    // Attendance totals per day.
    final attendance = <String, DayAttendance>{};
    for (final r in await rows('''
      SELECT date,
        SUM(CASE WHEN status = 'present' THEN 1 ELSE 0 END) AS p,
        SUM(CASE WHEN status = 'half' THEN 1 ELSE 0 END) AS h,
        SUM(CASE WHEN status = 'absent' THEN 1 ELSE 0 END) AS a
      FROM attendances WHERE date BETWEEN ? AND ? GROUP BY date
    ''', range)) {
      attendance[r.read<String>('date')] = DayAttendance(
        present: r.read<int>('p'),
        half: r.read<int>('h'),
        absent: r.read<int>('a'),
      );
    }

    final byDate = <String, List<CalendarEvent>>{};
    for (final e in events) {
      byDate.putIfAbsent(e.date, () => []).add(e);
    }
    for (final list in byDate.values) {
      list.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    }
    return CalendarMonth(
      month: first,
      events: byDate,
      attendance: attendance,
    );
  }
}

String _mode(Object? name) {
  final mode = PaymentMode.values.where((m) => m.name == name).firstOrNull;
  return switch (mode) {
    PaymentMode.cash => 'Cash',
    PaymentMode.phonePe => 'PhonePe',
    PaymentMode.paytm => 'Paytm',
    PaymentMode.gPay => 'GPay',
    PaymentMode.bank => 'Bank',
    null => '-',
  };
}

String _ledgerLabel(LedgerType type) => switch (type) {
      LedgerType.advance => 'Advance',
      LedgerType.payment => 'Payment',
      LedgerType.bonus => 'Bonus',
      LedgerType.deduction => 'Deduction',
      LedgerType.emi => 'Loan EMI',
      LedgerType.reversal => 'Reversal',
      LedgerType.carryForward => 'Carry forward',
    };
