// Enums are stored in SQLite by their `name`. Never rename or remove a value
// without a schema migration, or existing rows will fail to load.

/// Trades a contractor can work in (PRD C0). [seedFile] is the JSON file in
/// `assets/seed/` holding that trade's default roles, items and templates.
enum Trade {
  electrical('Electrical', 'electrical'),
  plumbing('Plumbing', 'plumbing'),
  civil('Civil / Construction', 'civil'),
  painting('Painting', 'painting'),
  tiles('Tiles / Flooring', 'tiles'),
  carpentry('Carpentry / Interior', 'carpentry'),
  pop('POP / False Ceiling', 'pop'),
  fabrication('Fabrication / Welding', 'fabrication'),
  labourSupply('Labour Supply', 'labour_supply'),
  other('Other', 'other');

  const Trade(this.label, this.seedFile);

  final String label;
  final String seedFile;

  /// Stored in `BusinessProfile.trades` as comma separated names.
  static String encode(Iterable<Trade> trades) {
    final sorted = trades.toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return sorted.map((t) => t.name).join(',');
  }

  static Set<Trade> decode(String value) => {
        for (final name in value.split(','))
          if (name.isNotEmpty) Trade.values.byName(name),
      };
}

enum UnitDimension { count, length, area, volume, weight, time, other }

enum WageModel { daily, monthly, piece }

enum AttendanceStatus { present, half, absent, leavePaid, leaveUnpaid, off }

enum PaymentMode { cash, phonePe, paytm, gPay, bank }

enum LedgerType {
  advance,
  payment,
  bonus,
  deduction,
  emi,
  reversal,
  carryForward,
}

enum SettlementStatus { locked, reversed }

enum ItemKind { material, workRate, labour }

enum LineType { material, labour, workRate, lumpSum }

enum DocumentKind { quotation, invoice }

enum DocumentStatus { draft, sent, partiallyPaid, paid, cancelled }

enum JobStatus { planned, inProgress, completed }

/// Supplier khata (PRD EX-02): material on credit, or money paid.
enum SupplierEntryType { purchase, payment }

enum AuditAction { create, update, reverse, delete }

enum BackupTrigger { scheduled, onChange, manual, internetBack, preRestore }

enum BackupStatus { success, failed, skipped }
