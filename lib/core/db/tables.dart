import 'package:drift/drift.dart';

import 'enums.dart';

// Conventions (PRD Part F):
// - ids are UUID text; money is INTEGER paise; quantities are INTEGER milli-units
// - calendar dates are 'yyyy-MM-dd' text; instants are epoch milliseconds
// - seeded master rows carry a unique `seedKey` so re-seeding never duplicates
//   or overwrites what the admin changed

/// Current time in epoch milliseconds.
int nowMs() => DateTime.now().millisecondsSinceEpoch;

mixin Timestamps on Table {
  IntColumn get createdAt => integer().clientDefault(nowMs)();
  IntColumn get updatedAt => integer().clientDefault(nowMs)();
}

// ─── Business & app ──────────────────────────────────────────────────────────

@DataClassName('BusinessProfile')
class BusinessProfiles extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get logoPath => text().nullable()();
  TextColumn get upiId => text().nullable()();
  TextColumn get signaturePath => text().nullable()();
  TextColumn get invoicePrefix => text().withDefault(const Constant('INV'))();
  TextColumn get quotationPrefix => text().withDefault(const Constant('QT'))();

  /// Comma separated [Trade] names, see [Trade.encode].
  TextColumn get trades => text().withDefault(const Constant(''))();
  TextColumn get settingsJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Key/value app state: dirtySince, deviceId, lastBackupAt, default_terms.
@DataClassName('AppMetaEntry')
class AppMeta extends Table {
  TextColumn get metaKey => text()();
  TextColumn get metaValue => text()();

  @override
  Set<Column<Object>> get primaryKey => {metaKey};
}

// ─── Master data (seeded per trade, editable) ───────────────────────────────

@DataClassName('Role')
class Roles extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sort => integer().withDefault(const Constant(0))();
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();
  TextColumn get seedKey => text().nullable().unique()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Unit')
class Units extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get code => text().unique()();
  TextColumn get name => text()();
  TextColumn get dimension => textEnum<UnitDimension>()();

  /// Factor to the dimension's base unit (m, sq.m, cu.m, kg) for conversion.
  /// Not money, so a REAL is fine here.
  RealColumn get toBase => real().nullable()();
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();
  TextColumn get seedKey => text().nullable().unique()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ExpenseCategory')
class ExpenseCategories extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sort => integer().withDefault(const Constant(0))();
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();
  TextColumn get seedKey => text().nullable().unique()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ItemMaster')
class ItemMasters extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get unitId => text().references(Units, #id)();
  TextColumn get kind => textEnum<ItemKind>()();

  /// Empty until the admin first bills it (rates differ per city, PRD D-8).
  IntColumn get defaultRatePaise => integer().nullable()();
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();
  TextColumn get seedKey => text().nullable().unique()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('BillTemplate')
class BillTemplates extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// `[{"itemSeedKey": "item:light_point", "name": "Light point"}, ...]`
  TextColumn get linesJson => text().withDefault(const Constant('[]'))();
  TextColumn get terms => text().nullable()();
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();
  TextColumn get seedKey => text().nullable().unique()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ─── Workers, attendance, khata ─────────────────────────────────────────────

@DataClassName('Worker')
class Workers extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  TextColumn get roleId => text().nullable().references(Roles, #id)();
  TextColumn get joinDate => text()();
  TextColumn get upiId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('WageHistory')
class WageHistories extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get workerId => text().references(Workers, #id)();
  TextColumn get model => textEnum<WageModel>()();

  /// Per day (daily), per month (monthly), 0 for piece-rate.
  IntColumn get ratePaise => integer()();
  IntColumn get otRatePaise => integer().withDefault(const Constant(0))();

  /// 30, 26, or 0 = days in that month (PRD I-S1).
  IntColumn get monthlyDivisor => integer().withDefault(const Constant(30))();
  TextColumn get effectiveFrom => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Attendance')
class Attendances extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get workerId => text().references(Workers, #id)();
  TextColumn get date => text()();
  TextColumn get status => textEnum<AttendanceStatus>()();
  IntColumn get otMilliHours => integer().withDefault(const Constant(0))();
  TextColumn get jobId => text().nullable().references(Jobs, #id)();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {workerId, date},
      ];
}

@DataClassName('Holiday')
class Holidays extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get date => text().unique()();
  TextColumn get name => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Piece-rate / theka work done by a worker (PRD WK-05).
@DataClassName('PieceWork')
class PieceWorks extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get workerId => text().references(Workers, #id)();
  TextColumn get date => text()();
  TextColumn get jobId => text().nullable().references(Jobs, #id)();
  TextColumn get itemId => text().nullable().references(ItemMasters, #id)();
  TextColumn get description => text()();
  IntColumn get qtyMilli => integer()();
  TextColumn get unitId => text().nullable().references(Units, #id)();
  IntColumn get ratePaise => integer()();
  IntColumn get amountPaise => integer()();
  TextColumn get settlementId =>
      text().nullable().references(Settlements, #id)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Immutable khata entries; mistakes are fixed with a reversal (PRD I-S4).
@DataClassName('LedgerEntry')
class LedgerEntries extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get workerId => text().references(Workers, #id)();
  TextColumn get entryType => textEnum<LedgerType>()();
  IntColumn get amountPaise => integer()();
  TextColumn get mode => textEnum<PaymentMode>().nullable()();
  IntColumn get at => integer()();
  TextColumn get remarks => text().nullable()();

  /// Reversed entry id, or settlement id for payments.
  TextColumn get refId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Settlement')
class Settlements extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get workerId => text().references(Workers, #id)();
  TextColumn get periodFrom => text()();
  TextColumn get periodTo => text()();
  IntColumn get earningPaise => integer()();
  IntColumn get advancePaise => integer()();
  IntColumn get emiPaise => integer().withDefault(const Constant(0))();
  IntColumn get paidPaise => integer()();
  IntColumn get carryForwardPaise => integer()();
  TextColumn get status => textEnum<SettlementStatus>()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ─── Billing ────────────────────────────────────────────────────────────────

@DataClassName('Client')
class Clients extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Job')
class Jobs extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get clientId => text().references(Clients, #id)();
  TextColumn get title => text()();
  TextColumn get siteAddress => text().nullable()();
  TextColumn get status => textEnum<JobStatus>()();
  IntColumn get contractValuePaise => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('BillDocument')
class Documents extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get kind => textEnum<DocumentKind>()();
  TextColumn get number => text()();
  TextColumn get clientId => text().references(Clients, #id)();
  TextColumn get jobId => text().nullable().references(Jobs, #id)();
  TextColumn get status => textEnum<DocumentStatus>()();
  TextColumn get date => text()();
  TextColumn get dueDate => text().nullable()();
  IntColumn get subtotalPaise => integer()();

  /// Discount entered as a percentage, in basis points (12.5% = 1250).
  /// Null when the discount was entered in rupees.
  IntColumn get discountPercentBp => integer().nullable()();
  IntColumn get discountPaise => integer().withDefault(const Constant(0))();
  BoolColumn get roundOff => boolean().withDefault(const Constant(true))();
  IntColumn get roundOffPaise => integer().withDefault(const Constant(0))();
  IntColumn get totalPaise => integer()();
  TextColumn get notes => text().nullable()();
  TextColumn get terms => text().nullable()();
  TextColumn get sourceQuotationId => text().nullable()();
  IntColumn get raStagePercent => integer().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {kind, number, revision},
      ];
}

@DataClassName('DocumentLine')
class DocumentLines extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get documentId => text().references(Documents, #id)();
  IntColumn get sort => integer()();
  TextColumn get lineType => textEnum<LineType>()();
  TextColumn get itemId => text().nullable().references(ItemMasters, #id)();
  TextColumn get name => text()();
  IntColumn get qtyMilli => integer()();
  TextColumn get unitId => text().nullable().references(Units, #id)();
  IntColumn get ratePaise => integer()();
  IntColumn get amountPaise => integer()();

  /// Measurement rows (PRD BL-16), see `MeasurementEntry.toJson`.
  TextColumn get measurementJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('PaymentReceived')
class PaymentsReceived extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get clientId => text().references(Clients, #id)();
  TextColumn get documentId => text().nullable().references(Documents, #id)();
  IntColumn get amountPaise => integer()();
  TextColumn get mode => textEnum<PaymentMode>()();
  TextColumn get date => text()();
  TextColumn get remarks => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ─── Expenses ───────────────────────────────────────────────────────────────

@DataClassName('Expense')
class Expenses extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get categoryId => text().references(ExpenseCategories, #id)();
  IntColumn get amountPaise => integer()();
  TextColumn get mode => textEnum<PaymentMode>()();
  TextColumn get date => text()();
  TextColumn get jobId => text().nullable().references(Jobs, #id)();
  TextColumn get photoPath => text().nullable()();
  TextColumn get remarks => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ─── Suppliers (schema v2, PRD EX-02) ───────────────────────────────────────

@DataClassName('Supplier')
class Suppliers extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Purchase on credit raises the due; payment lowers it.
@DataClassName('SupplierEntry')
class SupplierLedger extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get supplierId => text().references(Suppliers, #id)();
  TextColumn get entryType => textEnum<SupplierEntryType>()();
  IntColumn get amountPaise => integer()();
  TextColumn get mode => textEnum<PaymentMode>().nullable()();
  TextColumn get date => text()();
  TextColumn get billNo => text().nullable()();
  TextColumn get remarks => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ─── Audit & backup ─────────────────────────────────────────────────────────

@DataClassName('AuditLog')
class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get action => textEnum<AuditAction>()();
  TextColumn get beforeJson => text().nullable()();
  TextColumn get afterJson => text().nullable()();
  IntColumn get at => integer().clientDefault(nowMs)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('BackupLog')
class BackupLogs extends Table {
  TextColumn get id => text()();
  TextColumn get triggerType => textEnum<BackupTrigger>()();
  TextColumn get status => textEnum<BackupStatus>()();
  TextColumn get driveFileId => text().nullable()();
  IntColumn get sizeBytes => integer().nullable()();
  TextColumn get sha256 => text().nullable()();
  IntColumn get schemaVersion => integer()();
  IntColumn get startedAt => integer()();
  IntColumn get finishedAt => integer().nullable()();
  TextColumn get error => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
