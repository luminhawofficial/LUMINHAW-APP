import 'package:flutter/foundation.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';

enum PlanTier { free, premium }

class PlanEntitlementStore {
  PlanEntitlementStore._();

  static final instance = PlanEntitlementStore._();

  final ValueNotifier<PlanTier> tier = ValueNotifier(PlanTier.free);
  final ValueNotifier<bool> isRefreshing = ValueNotifier(false);
  final ValueNotifier<Object?> refreshError = ValueNotifier(null);

  bool get hasPremiumAccess => tier.value == PlanTier.premium;

  int _refreshGeneration = 0;
  String? _entitlementUserId;

  Future<void> refreshFromServer() async {
    final generation = ++_refreshGeneration;
    final user = SupabaseAuthService.currentUser;
    if (user == null || user.emailConfirmedAt == null) {
      tier.value = PlanTier.free;
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
          .select('product_id')
          .eq('user_id', user.id)
          .eq('status', 'active')
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .limit(1);
      if (_isCurrentRequest(generation, user.id)) {
        tier.value = entitlements.isEmpty ? PlanTier.free : PlanTier.premium;
        _entitlementUserId = user.id;
      }
    } catch (error) {
      if (_isCurrentRequest(generation, user.id)) {
        tier.value = PlanTier.free;
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
  }) {
    final user = SupabaseAuthService.currentUser;
    if (user == null || user.id != userId || user.emailConfirmedAt == null) {
      return;
    }
    _refreshGeneration++;
    _entitlementUserId = userId;
    tier.value = expiresAt != null && expiresAt.isAfter(DateTime.now().toUtc())
        ? PlanTier.premium
        : PlanTier.free;
    refreshError.value = null;
    isRefreshing.value = false;
  }

  bool _isCurrentRequest(int generation, String userId) =>
      generation == _refreshGeneration &&
      SupabaseAuthService.currentUser?.id == userId &&
      SupabaseAuthService.currentUser?.emailConfirmedAt != null;
}
