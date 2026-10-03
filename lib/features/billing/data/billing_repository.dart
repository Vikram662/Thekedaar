import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/audit.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/meta_store.dart';
import '../../../core/db/providers.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/measurement.dart';
import '../domain/document_totals.dart';

final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => BillingRepository(ref.watch(databaseProvider)),
);

final clientsProvider = StreamProvider<List<ClientBalance>>(
  (ref) => ref.watch(billingRepositoryProvider).watchClients(),
);

final clientProvider = StreamProvider.family<ClientBalance?, String>(
  (ref, id) => ref.watch(billingRepositoryProvider).watchClients().map(
        (all) => all.where((c) => c.client.id == id).firstOrNull,
      ),
);

final documentsProvider =
    StreamProvider.family<List<DocumentListItem>, DocumentKind>(
  (ref, kind) => ref.watch(billingRepositoryProvider).watchDocuments(kind),
);

final clientDocumentsProvider =
    StreamProvider.family<List<DocumentListItem>, String>(
  (ref, clientId) => ref
      .watch(billingRepositoryProvider)
      .watchDocuments(DocumentKind.invoice, clientId: clientId),
);

final documentDetailProvider = StreamProvider.family<DocumentDetail?, String>(
  (ref, id) => ref.watch(billingRepositoryProvider).watchDocument(id),
);

final paymentsProvider = StreamProvider.family<List<PaymentItem>, String?>(
  (ref, clientId) =>
      ref.watch(billingRepositoryProvider).watchPayments(clientId: clientId),
);

/// Total pending from all clients (PRD DB-01 pill).
final outstandingProvider = StreamProvider<int>(
  (ref) => ref.watch(billingRepositoryProvider).watchClients().map(
        (all) => all.fold(0, (sum, c) => sum + c.outstandingPaise),
      ),
);

final itemsProvider = StreamProvider<List<ItemWithUnit>>(
  (ref) => ref.watch(billingRepositoryProvider).watchItems(),
);

final unitsProvider = StreamProvider<List<Unit>>(
  (ref) => ref.watch(billingRepositoryProvider).watchUnits(),
);

final templatesProvider = StreamProvider<List<BillTemplate>>(
  (ref) => ref.watch(billingRepositoryProvider).watchTemplates(),
);

class ClientBalance {
  const ClientBalance({
    required this.client,
    required this.billedPaise,
    required this.receivedPaise,
  });

  final Client client;
  final int billedPaise;
  final int receivedPaise;

  int get outstandingPaise => billedPaise - receivedPaise;
}

class DocumentListItem {
  const DocumentListItem({
    required this.document,
    required this.clientName,
    required this.paidPaise,
  });

  final BillDocument document;
  final String clientName;
  final int paidPaise;

  int get balancePaise => document.totalPaise - paidPaise;
}

class DocumentDetail {
  const DocumentDetail({
    required this.document,
    required this.client,
    required this.lines,
    required this.paidPaise,
    this.convertedInvoiceId,
  });

  final BillDocument document;
  final Client client;
  final List<LineWithUnit> lines;
  final int paidPaise;

  /// For a quotation already converted (PRD BL-08).
  final String? convertedInvoiceId;

  int get balancePaise => document.totalPaise - paidPaise;
}

class LineWithUnit {
  const LineWithUnit({required this.line, this.unitCode});

  final DocumentLine line;
  final String? unitCode;

  List<MeasurementEntry> get measurement {
    final json = line.measurementJson;
    if (json == null || json.isEmpty) return const [];
    return [
      for (final row in jsonDecode(json) as List)
        MeasurementEntry.fromJson((row as Map).cast<String, dynamic>()),
    ];
  }

  DraftLine toDraft() => DraftLine(
        lineType: line.lineType,
        name: line.name,
        qtyMilli: line.qtyMilli,
        ratePaise: line.ratePaise,
        itemId: line.itemId,
        unitId: line.unitId,
        unitCode: unitCode,
        measurement: measurement,
      );
}

class ItemWithUnit {
  const ItemWithUnit({required this.item, required this.unit});

  final ItemMaster item;
  final Unit unit;
}

class PaymentItem {
  const PaymentItem({
    required this.payment,
    required this.clientName,
    this.documentNumber,
  });

  final PaymentReceived payment;
  final String clientName;
  final String? documentNumber;
}

/// Everything the editor saves (PRD BL-02..BL-05).
class DocumentDraft {
  const DocumentDraft({
    this.id,
    required this.kind,
    required this.clientId,
    this.jobId,
    required this.date,
    this.dueDate,
    required this.lines,
    this.discountPercentBp,
    this.discountPaise = 0,
    this.roundOff = true,
    this.notes,
    this.terms,
    this.sourceQuotationId,
  });

  final String? id;
  final DocumentKind kind;
  final String clientId;
  final String? jobId;
  final DateTime date;
  final DateTime? dueDate;
  final List<DraftLine> lines;
  final int? discountPercentBp;
  final int discountPaise;
  final bool roundOff;
  final String? notes;
  final String? terms;
  final String? sourceQuotationId;

  DocumentTotals get totals => computeTotals(
        lines.map((l) => l.amountPaise),
        discountPercentBp: discountPercentBp,
        discountPaise: discountPaise,
        roundOff: roundOff,
      );
}

class BillingRepository {
  BillingRepository(this._db);

  final AppDatabase _db;

  // ─── Clients (PRD BL-01) ──────────────────────────────────────────────────

  Stream<List<ClientBalance>> watchClients() {
    return _db.customSelect(
      '''
      SELECT c.*,
        COALESCE((SELECT SUM(d.total_paise) FROM documents d
          WHERE d.client_id = c.id AND d.kind = 'invoice'
            AND d.status NOT IN ('draft', 'cancelled')), 0) AS billed,
        COALESCE((SELECT SUM(p.amount_paise) FROM payments_received p
          WHERE p.client_id = c.id), 0) AS received
      FROM clients c
      ORDER BY c.name COLLATE NOCASE
      ''',
      readsFrom: {_db.clients, _db.documents, _db.paymentsReceived},
    ).watch().map((rows) => [
          for (final row in rows)
            ClientBalance(
              client: _db.clients.map(row.data),
              billedPaise: row.read<int>('billed'),
              receivedPaise: row.read<int>('received'),
            ),
        ]);
  }

  Future<String> saveClient({
    String? id,
    required String name,
    String? phone,
    String? address,
  }) async {
    if (id == null) {
      final newClientId = newId();
      await _db.into(_db.clients).insert(ClientsCompanion.insert(
            id: newClientId,
            name: name,
            phone: Value(phone),
            address: Value(address),
          ));
      return newClientId;
    }
    await (_db.update(_db.clients)..where((c) => c.id.equals(id))).write(
      ClientsCompanion(
        name: Value(name),
        phone: Value(phone),
        address: Value(address),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    return id;
  }

  // ─── Masters ──────────────────────────────────────────────────────────────

  Stream<List<ItemWithUnit>> watchItems() {
    final query = _db.select(_db.itemMasters).join([
      innerJoin(_db.units, _db.units.id.equalsExp(_db.itemMasters.unitId)),
    ])
      ..where(_db.itemMasters.isHidden.equals(false))
      ..orderBy([OrderingTerm.asc(_db.itemMasters.name)]);
    return query.watch().map((rows) => [
          for (final row in rows)
            ItemWithUnit(
              item: row.readTable(_db.itemMasters),
              unit: row.readTable(_db.units),
            ),
        ]);
  }

  Stream<List<Unit>> watchUnits() => (_db.select(_db.units)
        ..where((u) => u.isHidden.equals(false))
        ..orderBy([(u) => OrderingTerm.asc(u.name)]))
      .watch();

  Stream<List<BillTemplate>> watchTemplates() => (_db.select(_db.billTemplates)
        ..where((t) => t.isHidden.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();

  /// Template lines become draft lines with the items' remembered rates.
  Future<List<DraftLine>> linesFromTemplate(BillTemplate template) async {
    final keys = [
      for (final line in jsonDecode(template.linesJson) as List)
        (line as Map)['itemSeedKey'] as String,
    ];
    final items = await (_db.select(_db.itemMasters).join([
      innerJoin(_db.units, _db.units.id.equalsExp(_db.itemMasters.unitId)),
    ])
          ..where(_db.itemMasters.seedKey.isIn(keys)))
        .get();
    final byKey = {
      for (final row in items)
        row.readTable(_db.itemMasters).seedKey!: row,
    };
    return [
      for (final key in keys)
        if (byKey[key] != null)
          DraftLine(
            lineType: _lineTypeFor(byKey[key]!.readTable(_db.itemMasters).kind),
            name: byKey[key]!.readTable(_db.itemMasters).name,
            qtyMilli: 0,
            ratePaise:
                byKey[key]!.readTable(_db.itemMasters).defaultRatePaise ?? 0,
            itemId: byKey[key]!.readTable(_db.itemMasters).id,
            unitId: byKey[key]!.readTable(_db.units).id,
            unitCode: byKey[key]!.readTable(_db.units).code,
          ),
    ];
  }

  static LineType _lineTypeFor(ItemKind kind) => switch (kind) {
        ItemKind.material => LineType.material,
        ItemKind.workRate => LineType.workRate,
        ItemKind.labour => LineType.labour,
      };

  Future<String> defaultTerms() async =>
      await MetaStore(_db).get(MetaKeys.defaultTerms) ?? '';

  // ─── Documents ────────────────────────────────────────────────────────────

  Stream<List<DocumentListItem>> watchDocuments(
    DocumentKind kind, {
    String? clientId,
  }) {
    return _db.customSelect(
      '''
      SELECT d.*, c.name AS client_name,
        COALESCE((SELECT SUM(p.amount_paise) FROM payments_received p
          WHERE p.document_id = d.id), 0) AS paid
      FROM documents d JOIN clients c ON c.id = d.client_id
      WHERE d.kind = ? ${clientId == null ? '' : 'AND d.client_id = ?'}
      ORDER BY d.date DESC, d.number DESC
      ''',
      variables: [
        Variable.withString(kind.name),
        if (clientId != null) Variable.withString(clientId),
      ],
      readsFrom: {_db.documents, _db.clients, _db.paymentsReceived},
    ).watch().map((rows) => [
          for (final row in rows)
            DocumentListItem(
              document: _db.documents.map(row.data),
              clientName: row.read<String>('client_name'),
              paidPaise: row.read<int>('paid'),
            ),
        ]);
  }

  Stream<DocumentDetail?> watchDocument(String id) {
    final docQuery = _db.select(_db.documents)..where((d) => d.id.equals(id));
    return docQuery.watchSingleOrNull().asyncMap((doc) async {
      if (doc == null) return null;
      final client = await (_db.select(_db.clients)
            ..where((c) => c.id.equals(doc.clientId)))
          .getSingle();
      final lineRows = await (_db.select(_db.documentLines).join([
        leftOuterJoin(
            _db.units, _db.units.id.equalsExp(_db.documentLines.unitId)),
      ])
            ..where(_db.documentLines.documentId.equals(id))
            ..orderBy([OrderingTerm.asc(_db.documentLines.sort)]))
          .get();
      final paid = await _paidFor(id);
      final converted = doc.kind == DocumentKind.quotation
          ? await (_db.select(_db.documents)
                ..where((d) => d.sourceQuotationId.equals(id))
                ..limit(1))
              .getSingleOrNull()
          : null;
      return DocumentDetail(
        document: doc,
        client: client,
        lines: [
          for (final row in lineRows)
            LineWithUnit(
              line: row.readTable(_db.documentLines),
              unitCode: row.readTableOrNull(_db.units)?.code,
            ),
        ],
        paidPaise: paid,
        convertedInvoiceId: converted?.id,
      );
    });
  }

  Future<int> _paidFor(String documentId) async {
    final row = await _db.customSelect(
      'SELECT COALESCE(SUM(amount_paise), 0) AS paid '
      'FROM payments_received WHERE document_id = ?',
      variables: [Variable.withString(documentId)],
    ).getSingle();
    return row.read<int>('paid');
  }

  Future<String> _nextNumber(DocumentKind kind, DateTime date) async {
    final profile = await _db.select(_db.businessProfiles).getSingleOrNull();
    final prefix = kind == DocumentKind.invoice
        ? (profile?.invoicePrefix ?? 'INV')
        : (profile?.quotationPrefix ?? 'QT');
    final head = '$prefix/${financialYearLabel(date)}/';
    final rows = await (_db.select(_db.documents)
          ..where((d) => d.kind.equalsValue(kind) & d.number.like('$head%')))
        .get();
    final seq = nextSequence(rows.map((d) => d.number), head);
    return '$head${seq.toString().padLeft(4, '0')}';
  }

  /// Creates or updates a bill/quotation with its lines in one transaction.
  /// Editing a sent document bumps its revision (PRD I-B6). Item rates used
  /// here are remembered in the item master (PRD D-8).
  Future<String> saveDocument(DocumentDraft draft) async {
    final totals = draft.totals;
    late String id;
    await _db.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (draft.id == null) {
        id = newId();
        await _db.into(_db.documents).insert(DocumentsCompanion.insert(
              id: id,
              kind: draft.kind,
              number: await _nextNumber(draft.kind, draft.date),
              clientId: draft.clientId,
              jobId: Value(draft.jobId),
              status: DocumentStatus.draft,
              date: isoDate(draft.date),
              dueDate: Value(draft.dueDate == null ? null : isoDate(draft.dueDate!)),
              subtotalPaise: totals.subtotalPaise,
              discountPercentBp: Value(draft.discountPercentBp),
              discountPaise: Value(totals.discountPaise),
              roundOff: Value(draft.roundOff),
              roundOffPaise: Value(totals.roundOffPaise),
              totalPaise: totals.totalPaise,
              notes: Value(draft.notes),
              terms: Value(draft.terms),
              sourceQuotationId: Value(draft.sourceQuotationId),
            ));
        await writeAudit(_db,
            entity: 'document', entityId: id, action: AuditAction.create);
      } else {
        id = draft.id!;
        final before = await (_db.select(_db.documents)
              ..where((d) => d.id.equals(id)))
            .getSingle();
        final paid = await _paidFor(id);
        final bump = before.status != DocumentStatus.draft;
        await (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
          DocumentsCompanion(
            clientId: Value(draft.clientId),
            jobId: Value(draft.jobId),
            date: Value(isoDate(draft.date)),
            dueDate:
                Value(draft.dueDate == null ? null : isoDate(draft.dueDate!)),
            subtotalPaise: Value(totals.subtotalPaise),
            discountPercentBp: Value(draft.discountPercentBp),
            discountPaise: Value(totals.discountPaise),
            roundOff: Value(draft.roundOff),
            roundOffPaise: Value(totals.roundOffPaise),
            totalPaise: Value(totals.totalPaise),
            notes: Value(draft.notes),
            terms: Value(draft.terms),
            revision: Value(bump ? before.revision + 1 : before.revision),
            status: Value(before.kind == DocumentKind.invoice
                ? statusAfterPayments(before.status, totals.totalPaise, paid)
                : before.status),
            updatedAt: Value(now),
          ),
        );
        await writeAudit(_db,
            entity: 'document',
            entityId: id,
            action: AuditAction.update,
            before: before.toJson());
        await (_db.delete(_db.documentLines)
              ..where((l) => l.documentId.equals(id)))
            .go();
      }

      for (var i = 0; i < draft.lines.length; i++) {
        final line = draft.lines[i];
        await _db.into(_db.documentLines).insert(DocumentLinesCompanion.insert(
              id: newId(),
              documentId: id,
              sort: i,
              lineType: line.lineType,
              itemId: Value(line.itemId),
              name: line.name,
              qtyMilli: line.qtyMilli,
              unitId: Value(line.unitId),
              ratePaise: line.ratePaise,
              amountPaise: line.amountPaise,
              measurementJson: Value(line.measurement.isEmpty
                  ? null
                  : jsonEncode([for (final m in line.measurement) m.toJson()])),
            ));
        if (line.itemId != null && line.ratePaise > 0) {
          await (_db.update(_db.itemMasters)
                ..where((it) => it.id.equals(line.itemId!)))
              .write(ItemMastersCompanion(
            defaultRatePaise: Value(line.ratePaise),
            updatedAt: Value(now),
          ));
        }
      }
    });
    return id;
  }

  Future<void> setStatus(String id, DocumentStatus status) async {
    await (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
      DocumentsCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    await writeAudit(_db,
        entity: 'document',
        entityId: id,
        action: AuditAction.update,
        after: {'status': status.name});
  }

  /// Draft → Sent when shared (PRD BL-15).
  Future<void> markSentIfDraft(String id) async {
    final doc = await (_db.select(_db.documents)..where((d) => d.id.equals(id)))
        .getSingle();
    if (doc.status == DocumentStatus.draft) {
      await setStatus(id, DocumentStatus.sent);
    }
  }

  /// PRD BL-08: quotation → new invoice with the same lines. The quotation
  /// itself stays as it was (read-only snapshot).
  Future<String> convertToInvoice(String quotationId) async {
    final detail = await watchDocument(quotationId).first;
    if (detail == null) throw StateError('Quotation not found');
    final q = detail.document;
    return saveDocument(DocumentDraft(
      kind: DocumentKind.invoice,
      clientId: q.clientId,
      jobId: q.jobId,
      date: DateTime.now(),
      lines: [for (final l in detail.lines) l.toDraft()],
      discountPercentBp: q.discountPercentBp,
      discountPaise: q.discountPaise,
      roundOff: q.roundOff,
      notes: q.notes,
      terms: q.terms,
      sourceQuotationId: q.id,
    ));
  }

  // ─── Payments (PRD BL-13) ─────────────────────────────────────────────────

  Future<void> recordPayment({
    required String clientId,
    String? documentId,
    required int amountPaise,
    required PaymentMode mode,
    required DateTime date,
    String? remarks,
  }) async {
    if (amountPaise <= 0) throw ArgumentError('Amount must be more than 0');
    await _db.transaction(() async {
      final id = newId();
      await _db.into(_db.paymentsReceived).insert(
            PaymentsReceivedCompanion.insert(
              id: id,
              clientId: clientId,
              documentId: Value(documentId),
              amountPaise: amountPaise,
              mode: mode,
              date: isoDate(date),
              remarks: Value(remarks),
            ),
          );
      await writeAudit(_db,
          entity: 'payment',
          entityId: id,
          action: AuditAction.create,
          after: {'clientId': clientId, 'amountPaise': amountPaise});
      if (documentId != null) {
        final doc = await (_db.select(_db.documents)
              ..where((d) => d.id.equals(documentId)))
            .getSingle();
        final status = statusAfterPayments(
          doc.status == DocumentStatus.draft ? DocumentStatus.sent : doc.status,
          doc.totalPaise,
          await _paidFor(documentId),
        );
        if (status != doc.status) {
          await (_db.update(_db.documents)
                ..where((d) => d.id.equals(documentId)))
              .write(DocumentsCompanion(status: Value(status)));
        }
      }
    });
  }

  Stream<List<PaymentItem>> watchPayments({String? clientId}) {
    final query = _db.select(_db.paymentsReceived).join([
      innerJoin(
          _db.clients, _db.clients.id.equalsExp(_db.paymentsReceived.clientId)),
      leftOuterJoin(_db.documents,
          _db.documents.id.equalsExp(_db.paymentsReceived.documentId)),
    ]);
    if (clientId != null) {
      query.where(_db.paymentsReceived.clientId.equals(clientId));
    }
    query.orderBy([
      OrderingTerm.desc(_db.paymentsReceived.date),
      OrderingTerm.desc(_db.paymentsReceived.createdAt),
    ]);
    return query.watch().map((rows) => [
          for (final row in rows)
            PaymentItem(
              payment: row.readTable(_db.paymentsReceived),
              clientName: row.readTable(_db.clients).name,
              documentNumber: row.readTableOrNull(_db.documents)?.number,
            ),
        ]);
  }
}
