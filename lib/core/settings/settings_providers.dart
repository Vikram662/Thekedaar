import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../db/providers.dart';
import 'app_settings.dart';

final appSettingsProvider = StreamProvider<AppSettings>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.businessProfiles).watchSingleOrNull().map(
        (profile) => AppSettings.fromJsonString(profile?.settingsJson ?? '{}'),
      );
});

final settingsRepositoryProvider =
    Provider((ref) => SettingsRepository(ref.watch(databaseProvider)));

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Future<void> saveSettings(AppSettings settings) =>
      _db.update(_db.businessProfiles).write(BusinessProfilesCompanion(
            settingsJson: Value(settings.toJsonString()),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ));

  Future<void> saveProfile({
    required String name,
    String? phone,
    String? address,
    String? upiId,
    required String invoicePrefix,
    required String quotationPrefix,
  }) =>
      _db.update(_db.businessProfiles).write(BusinessProfilesCompanion(
            name: Value(name),
            phone: Value(phone),
            address: Value(address),
            upiId: Value(upiId),
            invoicePrefix: Value(invoicePrefix),
            quotationPrefix: Value(quotationPrefix),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ));

  Future<void> saveTrades(String encodedTrades) =>
      _db.update(_db.businessProfiles).write(BusinessProfilesCompanion(
            trades: Value(encodedTrades),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ));
}
