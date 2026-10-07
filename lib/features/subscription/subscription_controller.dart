import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/db/database.dart';
import '../../core/db/providers.dart';
import '../../core/i18n/i18n.dart';
import '../../core/security/secure_store.dart';
import 'data/subscription_service.dart';

enum AccessKind { loading, explore, active, offlineGrace, setupRequired }

class SubscriptionAccess {
  const SubscriptionAccess(this.kind,
      {this.status = 'none',
      this.subscriptionId,
      this.message,
      this.trialEndsAt,
      this.trialEligible = false});
  final AccessKind kind;
  final String status;
  final String? subscriptionId;
  final String? message;
  final int? trialEndsAt;
  final bool trialEligible;
  bool get isTrial => status == 'authenticated';
  bool get canWrite =>
      kind == AccessKind.active || kind == AccessKind.offlineGrace;
}

final subscriptionServiceProvider = Provider<SubscriptionService>(
    (ref) => SubscriptionService(ref.watch(secureStoreProvider)));

final subscriptionControllerProvider = StateNotifierProvider<
        SubscriptionController, AsyncValue<SubscriptionAccess>>(
    (ref) => SubscriptionController(
        ref.watch(subscriptionServiceProvider), ref.watch(databaseProvider)));

class SubscriptionController
    extends StateNotifier<AsyncValue<SubscriptionAccess>> {
  SubscriptionController(this._service, this._db)
      : super(const AsyncData(SubscriptionAccess(AccessKind.loading)));

  final SubscriptionService _service;
  final AppDatabase _db;

  Future<BusinessProfile?> _profile() =>
      _db.select(_db.businessProfiles).getSingleOrNull();

  Future<void> refresh() async {
    if (!AppConfig.subscriptionConfigured) {
      state = AsyncData(SubscriptionAccess(AccessKind.setupRequired,
          message: tr('Subscription service is not configured.')));
      return;
    }
    state = const AsyncLoading();
    try {
      final profile = await _profile();
      if (profile == null) {
        state = const AsyncData(SubscriptionAccess(AccessKind.explore));
        return;
      }
      Map<String, dynamic> data;
      try {
        data = await _service.status();
      } on SubscriptionApiException catch (error) {
        if (!error.message.contains('Registration')) rethrow;
        final restored = await _service.cached();
        await _service.register(profile.name, profile.phone);
        final restoredId = restored['subscriptionId'];
        data = restoredId != null && restoredId.isNotEmpty
            ? await _service.link(restoredId)
            : await _service.status();
      }
      state = AsyncData(_fromApi(data));
    } catch (error, stack) {
      final cached = await _service.cached();
      final verifiedAt = int.tryParse(cached['verifiedAt'] ?? '') ?? 0;
      final grace = cached['status'] == 'active' &&
          DateTime.now().millisecondsSinceEpoch - verifiedAt <=
              const Duration(days: 7).inMilliseconds;
      if (grace) {
        state = AsyncData(SubscriptionAccess(AccessKind.offlineGrace,
            status: 'active',
            subscriptionId: cached['subscriptionId'],
            message: tr('Offline access — connect within 7 days.')));
      } else {
        state = AsyncError(error, stack);
      }
    }
  }

  Future<void> registerProfile(BusinessProfile profile) async {
    if (!AppConfig.subscriptionConfigured) return;
    await _service.register(profile.name, profile.phone);
    await refresh();
  }

  Future<CheckoutSession> createCheckout() => _service.createSubscription();

  Future<void> link(String id) async {
    state = const AsyncLoading();
    try {
      state = AsyncData(_fromApi(await _service.link(id)));
    } catch (error, stack) {
      state = AsyncError(error, stack);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> cancel() async {
    final result = await _service.cancel();
    state = AsyncData(_fromApi(result));
    return result;
  }

  SubscriptionAccess _fromApi(Map<String, dynamic> data) {
    final status = data['status'] as String? ?? 'none';
    final active = data['active'] == true || status == 'active';
    return SubscriptionAccess(active ? AccessKind.active : AccessKind.explore,
        status: status,
        subscriptionId: data['subscriptionId'] as String?,
        trialEndsAt: data['trialEndsAt'] as int?,
        trialEligible: data['trialEligible'] == true);
  }
}
