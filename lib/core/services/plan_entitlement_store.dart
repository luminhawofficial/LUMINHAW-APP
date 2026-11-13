import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:luminhaw/core/services/premium_payment_service.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  String? _realtimeUserId;
  RealtimeChannel? _entitlementChannel;
  Timer? _expirationTimer;

  Future<void> refreshFromServer() async {
    final generation = ++_refreshGeneration;
    final initialUser = SupabaseAuthService.currentUser;
    if (initialUser == null) {
      _stopRealtimeSubscription();
      _clearEntitlement();
      _entitlementUserId = null;
      refreshError.value = null;
      isRefreshing.value = false;
      return;
    }

    final userId = initialUser.id;
    _ensureRealtimeSubscription(userId);
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

  void _ensureRealtimeSubscription(String userId) {
    if (!SupabaseBackend.isInitialized ||
        (_realtimeUserId == userId && _entitlementChannel != null)) {
      return;
    }

    _stopRealtimeSubscription();
    _realtimeUserId = userId;
    _entitlementChannel = SupabaseBackend.client
        .channel('premium-entitlement-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'subscription_entitlements',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            if (SupabaseAuthService.currentUser?.id == userId) {
              unawaited(_refreshAfterEntitlementChange(userId));
            }
          },
        )
        .subscribe();
  }

  Future<void> _refreshAfterEntitlementChange(String userId) async {
    try {
      if (SupabaseAuthService.currentUser?.id == userId) {
        await refreshFromServer();
      }
    } catch (error) {
      debugPrint('Subscription refresh after server update failed: $error');
    }
  }

  void _stopRealtimeSubscription() {
    final channel = _entitlementChannel;
    _entitlementChannel = null;
    _realtimeUserId = null;
    if (channel != null && SupabaseBackend.isInitialized) {
      unawaited(_removeRealtimeChannel(channel));
    }
  }

  Future<void> _removeRealtimeChannel(RealtimeChannel channel) async {
    try {
      await SupabaseBackend.client.removeChannel(channel);
    } catch (error) {
      debugPrint('Subscription realtime cleanup failed: $error');
    }
  }
}
