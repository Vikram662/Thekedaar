import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/seed/seed_service.dart';

const businessProfileId = 'main';

final seedServiceProvider = Provider<SeedService>(
  (ref) => SeedService(
    ref.watch(databaseProvider),
    (name) => rootBundle.loadString('assets/seed/$name.json'),
  ),
);

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => OnboardingRepository(
    ref.watch(databaseProvider),
    ref.watch(seedServiceProvider),
  ),
);

class OnboardingRepository {
  OnboardingRepository(this._db, this._seed);

  final AppDatabase _db;
  final SeedService _seed;

  /// Seeds the trades' defaults, then saves the profile. The profile is
  /// written last, so if seeding fails the app opens onboarding again and the
  /// (idempotent) seed simply runs once more.
  Future<void> complete({
    required String businessName,
    required String? phone,
    required Set<Trade> trades,
  }) async {
    await _seed.applyTrades(trades);
    await _db.into(_db.businessProfiles).insertOnConflictUpdate(
          BusinessProfilesCompanion.insert(
            id: businessProfileId,
            name: businessName,
            phone: Value(phone),
            trades: Value(Trade.encode(trades)),
          ),
        );
  }
}
