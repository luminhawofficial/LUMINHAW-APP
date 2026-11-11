import 'dart:async';

import 'package:flutter/foundation.dart';
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
    final user = SupabaseAuthService.currentUser;
    if (user == null || user.emailConfirmedAt == null) {
      _clearEntitlement();
      _entitlementUserId = null;
      refreshError.value = null;
      isRefreshing.value = false;
      return;
    }

    if (_entitlementUserId != user.id) {
      tier.value = PlanTier.free;
      _entitlementUserId = null;
    }
    isRefreshing.value = true;
    refreshError.value = null;

    try {
      final entitlements = await SupabaseBackend.client
          .from('subscription_entitlements')
          .select('product_id, status, verified_at, expires_at, updated_at')
          .eq('user_id', user.id)
          .order('updated_at', ascending: false)
          .limit(20);
      if (_isCurrentRequest(generation, user.id)) {
        final rows = entitlements
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
        final now = DateTime.now().toUtc();
        final current = rows.cast<Map<String, dynamic>?>().firstWhere(
          (row) =>
              row?['status'] == 'active' &&
              DateTime.tryParse('${row?['expires_at']}')?.isAfter(now) == true,
          orElse: () => null,
        );
        final latest = rows.isEmpty ? null : rows.first;
        final selected = current ?? latest;
        final expiration = DateTime.tryParse('${selected?['expires_at']}');
        final active =
            selected?['status'] == 'active' &&
            expiration != null &&
            expiration.isAfter(now);
        _applySnapshot(
          productId: selected?['product_id'] as String?,
          status: selected?['status'] as String?,
          startsAt: DateTime.tryParse('${selected?['verified_at']}'),
          expiresAt: expiration,
          active: active,
        );
        _entitlementUserId = user.id;
      }
    } catch (error) {
      if (_isCurrentRequest(generation, user.id)) {
        _clearEntitlement();
        _entitlementUserId = null;
        refreshError.value = error;
      }
      rethrow;
    } finally {
      if (_isCurrentRequest(generation, user.id)) {
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
}
