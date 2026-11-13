import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:luminhaw/core/services/premium_payment_service.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';

enum PlanTier { free, premium }

class PlanEntitlementStore {
  PlanEntitlementStore._();

  static final instance = PlanEntitlementStore._();

  final ValueNotifier<PlanTier> tier = ValueNotifier(PlanTier.free);
  final ValueNotifier<bool> isRefreshing = ValueNotifier(false);
  final ValueNotifier<Object?> refreshError = ValueNotifier(null);
  final ValueNotifier<String?> productCode = ValueNotifier(null);
  final ValueNotifier<String> subscriptionStatus = ValueNotifier('Free');
  final ValueNotifier<DateTime?> startsAt = ValueNotifier(null);
  final ValueNotifier<DateTime?> expiresAt = ValueNotifier(null);

  bool get hasPremiumAccess =>
      tier.value == PlanTier.premium &&
      expiresAt.value != null &&
      expiresAt.value!.isAfter(DateTime.now().toUtc());

  int _refreshGeneration = 0;
  String? _entitlementUserId;
  Timer? _expirationTimer;

  Future<void> refreshFromServer() async {
    final generation = ++_refreshGeneration;
    final initialUser = SupabaseAuthService.currentUser;
    if (initialUser == null) {
      _clearEntitlement();
      _entitlementUserId = null;
      refreshError.value = null;
      isRefreshing.value = false;
      return;
    }

    final userId = initialUser.id;
    if (_entitlementUserId != userId) {
      tier.value = PlanTier.free;
      _entitlementUserId = null;
    }
    isRefreshing.value = true;
    refreshError.value = null;

    try {
      final options = await PremiumPaymentService.loadOptions();
      if (_isCurrentRequest(generation, userId)) {
        if (options.userId != userId) {
          throw StateError(
            'The payment status belongs to a different account.',
          );
        }
        final expiration = options.premiumExpiresAt;
        final active =
            options.premiumStatus == 'active' &&
            expiration != null &&
            expiration.isAfter(DateTime.now().toUtc());
        _applySnapshot(
          productId: options.premiumProductId,
          status: options.premiumStatus,
          startsAt: options.premiumStartsAt,
          expiresAt: expiration,
          active: active,
        );
        _entitlementUserId = userId;
      }
    } catch (error) {
      if (_isCurrentGenerationForUser(generation, userId)) {
        _clearEntitlement();
        _entitlementUserId = null;
        refreshError.value = error;
      }
      rethrow;
    } finally {
      if (_isCurrentGenerationForUser(generation, userId)) {
        isRefreshing.value = false;
      }
    }
  }

  void applyVerifiedServerSnapshot({
    required String userId,
    required DateTime? expiresAt,
    String? productId,
    String? status,
    DateTime? startsAt,
  }) {
    final user = SupabaseAuthService.currentUser;
    if (user == null || user.id != userId || user.emailConfirmedAt == null) {
      return;
    }
    _refreshGeneration++;
    _entitlementUserId = userId;
    final active =
        status == 'active' &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now().toUtc());
    _applySnapshot(
      productId: productId,
      status: status,
      startsAt: startsAt,
      expiresAt: expiresAt,
      active: active,
    );
    refreshError.value = null;
    isRefreshing.value = false;
  }

  void _applySnapshot({
    required String? productId,
    required String? status,
    required DateTime? startsAt,
    required DateTime? expiresAt,
    required bool active,
  }) {
    _expirationTimer?.cancel();
    productCode.value = productId;
    this.startsAt.value = startsAt?.toUtc();
    this.expiresAt.value = expiresAt?.toUtc();
    subscriptionStatus.value = active
        ? 'Active'
        : status == 'expired' || (status == 'active' && expiresAt != null)
        ? 'Expired'
        : status == 'revoked'
        ? 'Revoked'
        : 'Free';
    tier.value = active ? PlanTier.premium : PlanTier.free;
    if (active && expiresAt != null) {
      final delay = expiresAt.difference(DateTime.now().toUtc());
      _expirationTimer = Timer(delay, () {
        tier.value = PlanTier.free;
        subscriptionStatus.value = 'Expired';
      });
    }
  }

  void _clearEntitlement() {
    _expirationTimer?.cancel();
    productCode.value = null;
    subscriptionStatus.value = 'Free';
    startsAt.value = null;
    expiresAt.value = null;
    tier.value = PlanTier.free;
  }

  bool _isCurrentRequest(int generation, String userId) =>
      generation == _refreshGeneration &&
      SupabaseAuthService.currentUser?.id == userId &&
      SupabaseAuthService.currentUser?.emailConfirmedAt != null;

  bool _isCurrentGenerationForUser(int generation, String userId) =>
      generation == _refreshGeneration &&
      SupabaseAuthService.currentUser?.id == userId;
}
