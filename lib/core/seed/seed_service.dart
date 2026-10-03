import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/database.dart';
import '../db/enums.dart';
import '../utils/ids.dart';

/// Returns the JSON text of `assets/seed/<name>.json`.
typedef SeedReader = Future<String> Function(String name);

String roleSeedKey(String name) => 'role:${slug(name)}';
String unitSeedKey(String code) => 'unit:$code';
String categorySeedKey(String name) => 'cat:${slug(name)}';
String itemSeedKey(String name) => 'item:${slug(name)}';
String templateSeedKey(String name) => 'tpl:${slug(name)}';

/// Inserts the default master data for the chosen trades (PRD C0, Part J).
///
/// Idempotent: every seeded row has a unique `seedKey` and is inserted with
/// INSERT OR IGNORE, so running it again (or for a trade added later, TR-05)
/// only adds what is missing and never touches rows the admin edited,
/// renamed or hid.
class SeedService {
  SeedService(this._db, this._read);

  final AppDatabase _db;
  final SeedReader _read;

  Future<void> applyTrades(Iterable<Trade> trades) async {
    final common = await _load('common');
    final packs = [
      common,
      for (final trade in trades.toSet()) await _load(trade.seedFile),
    ];

    await _db.transaction(() async {
      await _seedUnits(common);
      final unitIds = await _unitIdsBySeedKey();
      for (var i = 0; i < packs.length; i++) {
        // Common roles/categories first, then each trade's.
        final sort = i * 10;
        await _seedRoles(packs[i], sort);
        await _seedExpenseCategories(packs[i], sort);
        await _seedItems(packs[i], unitIds);
        await _seedTemplates(packs[i]);
      }
      final terms = common['defaultTerms'] as List? ?? const [];
      await _db.into(_db.appMeta).insert(
            AppMetaCompanion.insert(
              metaKey: 'default_terms',
              metaValue: terms.join('\n'),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    });
  }

  Future<Map<String, dynamic>> _load(String name) async =>
      jsonDecode(await _read(name)) as Map<String, dynamic>;

  Future<void> _seedUnits(Map<String, dynamic> pack) async {
    for (final raw in pack['units'] as List? ?? const []) {
      final unit = raw as Map<String, dynamic>;
      final code = unit['code'] as String;
      await _db.into(_db.units).insert(
            UnitsCompanion.insert(
              id: newId(),
              code: code,
              name: unit['name'] as String,
              dimension:
                  UnitDimension.values.byName(unit['dimension'] as String),
              toBase: Value((unit['toBase'] as num?)?.toDouble()),
              seedKey: Value(unitSeedKey(code)),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<Map<String, String>> _unitIdsBySeedKey() async {
    final units = await _db.select(_db.units).get();
    return {
      for (final unit in units)
        if (unit.seedKey != null) unit.seedKey!: unit.id,
    };
  }

  Future<void> _seedRoles(Map<String, dynamic> pack, int sort) async {
    for (final raw in pack['roles'] as List? ?? const []) {
      final name = raw as String;
      await _db.into(_db.roles).insert(
            RolesCompanion.insert(
              id: newId(),
              name: name,
              sort: Value(sort),
              seedKey: Value(roleSeedKey(name)),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<void> _seedExpenseCategories(
    Map<String, dynamic> pack,
    int sort,
  ) async {
    for (final raw in pack['expenseCategories'] as List? ?? const []) {
      final name = raw as String;
      await _db.into(_db.expenseCategories).insert(
            ExpenseCategoriesCompanion.insert(
              id: newId(),
              name: name,
              sort: Value(sort),
              seedKey: Value(categorySeedKey(name)),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<void> _seedItems(
    Map<String, dynamic> pack,
    Map<String, String> unitIds,
  ) async {
    for (final raw in pack['items'] as List? ?? const []) {
      final item = raw as Map<String, dynamic>;
      final name = item['name'] as String;
      final unitCode = item['unit'] as String;
      final unitId = unitIds[unitSeedKey(unitCode)];
      if (unitId == null) {
        throw StateError('Seed item "$name" uses unknown unit "$unitCode"');
      }
      await _db.into(_db.itemMasters).insert(
            ItemMastersCompanion.insert(
              id: newId(),
              name: name,
              unitId: unitId,
              kind: ItemKind.values.byName(item['kind'] as String),
              seedKey: Value(itemSeedKey(name)),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<void> _seedTemplates(Map<String, dynamic> pack) async {
    for (final raw in pack['templates'] as List? ?? const []) {
      final template = raw as Map<String, dynamic>;
      final name = template['name'] as String;
      final lines = [
        for (final line in template['lines'] as List? ?? const [])
          {'itemSeedKey': itemSeedKey(line as String), 'name': line},
      ];
      await _db.into(_db.billTemplates).insert(
            BillTemplatesCompanion.insert(
              id: newId(),
              name: name,
              linesJson: Value(jsonEncode(lines)),
              seedKey: Value(templateSeedKey(name)),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }
}
